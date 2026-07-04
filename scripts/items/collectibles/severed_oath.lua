ConchBlessing.severedoath = ConchBlessing.severedoath or {}
local M = ConchBlessing.severedoath

local SEVERED_OATH_ID = Isaac.GetItemIdByName("Severed Oath")
local SPLIT_SPACING = 40
local MIN_PICKUP_WAIT = 20
local MAX_COLLECTIBLE_CYCLE_ITEMS = 8
local EXTRA_CYCLE_PICK_ATTEMPTS = 12
local CONTINUED_PICKUP_LOAD_SUPPRESS_FRAMES = 15
local SPLIT_MARKER = "__conchBlessingSeveredOathSplit"
local SPLIT_ITEM_MARKER = "__conchBlessingSeveredOathSplitItem"
local CYCLE_ELIGIBLE_MARKER = "__conchBlessingSeveredOathCycleEligible"
local CYCLE_DONE_MARKER = "__conchBlessingSeveredOathCycleDone"
local CYCLE_INIT_FRAME_MARKER = "__conchBlessingSeveredOathCycleInitFrame"
local CYCLE_POOL_MARKER = "__conchBlessingSeveredOathCyclePool"
local SAVE_KEY = "severedOath"

local ACTIVE_SLOTS = {
    (ActiveSlot and (ActiveSlot.SLOT_PRIMARY or ActiveSlot.PRIMARY)) or 0,
    (ActiveSlot and (ActiveSlot.SLOT_SECONDARY or ActiveSlot.SECONDARY)) or 1,
    (ActiveSlot and (ActiveSlot.SLOT_POCKET or ActiveSlot.POCKET)) or 2,
    (ActiveSlot and (ActiveSlot.SLOT_POCKET2 or ActiveSlot.POCKET_SINGLE_USE)) or 3,
}

local CYCLE_MODIFIER_ITEMS = {
    (CollectibleType and (CollectibleType.COLLECTIBLE_GLITCHED_CROWN or CollectibleType.GLITCHED_CROWN)) or 689,
    (CollectibleType and (CollectibleType.COLLECTIBLE_BIRTHRIGHT or CollectibleType.BIRTHRIGHT)) or 619,
    (CollectibleType and (CollectibleType.COLLECTIBLE_BINGE_EATER or CollectibleType.BINGE_EATER)) or 664,
}

M.data = M.data or {}
M._cyclePickupStates = M._cyclePickupStates or {}
M._cycleRoomKey = M._cycleRoomKey or nil
M._cycleRoomLoadFrame = M._cycleRoomLoadFrame or 0
M._pendingPoolChecks = M._pendingPoolChecks or {}
M._suppressContinuedPickupCyclesUntil = M._suppressContinuedPickupCyclesUntil or nil
M._continuedRun = M._continuedRun or false

local function isValidCollectibleId(itemId)
    if type(itemId) ~= "number" or itemId <= 0 then
        return false
    end

    local config = Isaac.GetItemConfig()
    return config and config:GetCollectible(itemId) ~= nil
end

local function addUniqueItem(ids, seen, itemId)
    if not isValidCollectibleId(itemId) or seen[itemId] then
        return
    end

    seen[itemId] = true
    table.insert(ids, itemId)
end

local function getCollectibleCycleValues(pickup)
    if not pickup or pickup.Variant ~= PickupVariant.PICKUP_COLLECTIBLE then
        return {}
    end

    if type(pickup.GetCollectibleCycle) ~= "function" then
        return {}
    end

    local ok, cycle = pcall(function()
        return pickup:GetCollectibleCycle()
    end)
    if not ok or type(cycle) ~= "table" then
        return {}
    end

    local ids = {}
    local function addRawItem(itemId)
        if isValidCollectibleId(itemId) then
            table.insert(ids, itemId)
        end
    end

    for _, itemId in ipairs(cycle) do
        addRawItem(itemId)
    end
    if #ids <= 0 then
        for _, itemId in pairs(cycle) do
            addRawItem(itemId)
        end
    end

    return ids
end

local function getRawCycleItems(pickup)
    local ids = {}
    local seen = {}

    for _, itemId in ipairs(getCollectibleCycleValues(pickup)) do
        addUniqueItem(ids, seen, itemId)
    end

    return ids
end

local function getCycleItems(pickup)
    local ids = {}
    local seen = {}

    for _, itemId in ipairs(getRawCycleItems(pickup)) do
        addUniqueItem(ids, seen, itemId)
    end
    addUniqueItem(ids, seen, pickup and pickup.SubType)

    return ids
end

local function formatItemList(items)
    local parts = {}
    for _, itemId in ipairs(items or {}) do
        table.insert(parts, tostring(itemId))
    end
    return table.concat(parts, ",")
end

local function getPickupOptionsIndex(pickup)
    return math.max(0, tonumber(pickup and pickup.OptionsPickupIndex) or 0)
end

local function getCurrentRoomKey()
    local game = Game()
    local level = game:GetLevel()
    local roomIndex = level and level:GetCurrentRoomIndex() or -1
    local dimension = 0
    if level and type(level.GetDimension) == "function" then
        local ok, currentDimension = pcall(function()
            return level:GetDimension()
        end)
        if ok and type(currentDimension) == "number" then
            dimension = currentDimension
        end
    end

    return tostring(roomIndex) .. ":" .. tostring(dimension)
end

local function ensureCycleRoomState()
    local roomKey = getCurrentRoomKey()
    if M._cycleRoomKey ~= roomKey then
        M._cyclePickupStates = {}
        M._cycleRoomKey = roomKey
        M._cycleRoomLoadFrame = Game():GetFrameCount()
    end
end

local function getPickupCycleKey(pickup)
    if not pickup then
        return nil
    end

    local initSeed = tonumber(pickup.InitSeed) or 0
    if initSeed ~= 0 then
        return tostring(initSeed)
    end
    if GetPtrHash then
        return "ptr:" .. tostring(GetPtrHash(pickup))
    end
    return nil
end

local function getPickupSaveState(pickup, create)
    local saveManager = ConchBlessing and ConchBlessing.SaveManager
    local methodName = create and "GetNoRerollPickupSave" or "TryGetNoRerollPickupSave"
    if not saveManager or type(saveManager[methodName]) ~= "function" then
        return nil
    end

    local ok, pickupSave = pcall(function()
        return saveManager[methodName](pickup)
    end)
    if not ok or type(pickupSave) ~= "table" then
        return nil
    end

    if create then
        pickupSave[SAVE_KEY] = pickupSave[SAVE_KEY] or {}
    end
    return pickupSave[SAVE_KEY]
end

local function saveManagerSave()
    local saveManager = ConchBlessing and ConchBlessing.SaveManager
    if saveManager and type(saveManager.Save) == "function" then
        pcall(function()
            saveManager.Save()
        end)
    end
end

local function getSavedSplitItem(pickup)
    local save = getPickupSaveState(pickup, false)
    if type(save) ~= "table" or save.split ~= true then
        return nil
    end
    local splitItem = tonumber(save.splitItem)
    if not splitItem and isValidCollectibleId(tonumber(pickup and pickup.SubType)) then
        splitItem = tonumber(pickup.SubType)
        save.splitItem = splitItem
        saveManagerSave()
    end
    return splitItem
end

local function markSavedSplitPickup(pickup, itemId)
    local save = getPickupSaveState(pickup, true)
    if type(save) ~= "table" then
        return
    end

    save.split = true
    save.splitItem = tonumber(itemId) or tonumber(pickup and pickup.SubType)
    save.poolType = nil
    save.bonusItem = nil
    save.bonusSeen = nil
    saveManagerSave()
end

local function clearSavedSplitPickup(pickup)
    local save = getPickupSaveState(pickup, false)
    if type(save) ~= "table" or save.split ~= true then
        return
    end

    save.split = false
    save.splitItem = nil
    saveManagerSave()
end

local function getSavedBonusState(pickup)
    local save = getPickupSaveState(pickup, false)
    if type(save) ~= "table" or not isValidCollectibleId(save.bonusItem) then
        return nil
    end
    return save
end

local function isContinuedPickupLoadFrame()
    local suppressUntil = tonumber(M._suppressContinuedPickupCyclesUntil)
    if suppressUntil ~= nil and Game():GetFrameCount() <= suppressUntil then
        return true
    end

    if M._continuedRun ~= true then
        return false
    end

    local room = Game():GetRoom()
    if not room or room:IsFirstVisit() then
        return false
    end

    if Game():GetFrameCount() <= CONTINUED_PICKUP_LOAD_SUPPRESS_FRAMES then
        return true
    end

    return Game():GetFrameCount() <= (tonumber(M._cycleRoomLoadFrame) or 0) + CONTINUED_PICKUP_LOAD_SUPPRESS_FRAMES
end

local function markSavedBonusState(pickup, state)
    if not (state and state.bonusItem) then
        return
    end

    local save = getPickupSaveState(pickup, true)
    if type(save) ~= "table" then
        return
    end

    save.split = false
    save.poolType = tonumber(state.poolType) or 0
    save.bonusItem = tonumber(state.bonusItem)
    save.bonusSeen = state.bonusSeen == true
    saveManagerSave()
end

local function writeCycleStateToPickup(pickup, state)
    if not pickup or not state then
        return
    end

    local data = pickup:GetData()
    data[CYCLE_ELIGIBLE_MARKER] = state.eligible
    data[CYCLE_DONE_MARKER] = state.done
    data[CYCLE_INIT_FRAME_MARKER] = state.initFrame
    data[CYCLE_POOL_MARKER] = state.poolType
end

local function setPickupCycleState(pickup, state)
    ensureCycleRoomState()

    local key = getPickupCycleKey(pickup)
    if key then
        M._cyclePickupStates[key] = state
    end
    writeCycleStateToPickup(pickup, state)
end

local function getPickupCycleState(pickup)
    ensureCycleRoomState()

    local key = getPickupCycleKey(pickup)
    return key and M._cyclePickupStates[key] or nil
end

local function updateBonusSeen(pickup, state)
    if not (pickup and state and state.bonusItem) then
        return
    end
    if pickup.SubType ~= state.bonusItem then
        return
    end

    state.bonusSeen = true
    writeCycleStateToPickup(pickup, state)
    markSavedBonusState(pickup, state)
end

local function getRoomPoolType()
    local game = Game()
    local pool = game:GetItemPool()
    local room = game:GetRoom()
    if not pool or not room then
        return 0
    end

    local ok, poolType = pcall(function()
        return pool:GetPoolForRoom(room:GetType(), room:GetSpawnSeed())
    end)
    if ok and type(poolType) == "number" and poolType >= 0 then
        return poolType
    end

    return 0
end

local function getLastPoolType()
    local pool = Game():GetItemPool()
    if pool and type(pool.GetLastPool) == "function" then
        local ok, poolType = pcall(function()
            return pool:GetLastPool()
        end)
        if ok and type(poolType) == "number" and poolType >= 0 then
            return poolType
        end
    end

    return getRoomPoolType()
end

local function countMapEntries(map)
    local count = 0
    if type(map) ~= "table" then
        return count
    end

    for _ in pairs(map) do
        count = count + 1
    end
    return count
end

local function getPoolItemField(poolItem, lowerName, upperName, fallbackIndex)
    if type(poolItem) ~= "table" then
        return nil
    end

    local value = poolItem[lowerName]
    if value == nil then
        value = poolItem[upperName]
    end
    if value == nil and fallbackIndex then
        value = poolItem[fallbackIndex]
    end
    return value
end

local function getPoolItemId(poolItem)
    return tonumber(getPoolItemField(poolItem, "itemID", "ItemID", 1))
        or tonumber(getPoolItemField(poolItem, "itemId", "ItemId", nil))
        or tonumber(getPoolItemField(poolItem, "id", "ID", nil))
        or tonumber(getPoolItemField(poolItem, "collectible", "Collectible", nil))
end

local function copyRemovedCollectibles(pool)
    local removedItems = {}
    if not pool or type(pool.GetRemovedCollectibles) ~= "function" then
        return removedItems, nil
    end

    local removedOk, removed = pcall(function()
        return pool:GetRemovedCollectibles()
    end)
    if not removedOk or type(removed) ~= "table" then
        return removedItems, nil
    end

    local count = 0
    for itemId, value in pairs(removed) do
        local numericId
        if value == true or value == "true" then
            numericId = tonumber(itemId)
        elseif type(value) == "number" then
            numericId = value
        elseif type(value) == "string" then
            numericId = tonumber(value)
        end
        if numericId then
            removedItems[numericId] = true
            count = count + 1
        end
    end
    return removedItems, count
end

local function getPoolStats(poolType)
    local stats = {
        poolType = tonumber(poolType) or 0,
        ok = false,
        entries = 0,
        available = 0,
        totalWeight = 0,
        removedAll = nil,
        removedItems = {},
        items = {},
        error = nil,
    }

    local pool = Game():GetItemPool()
    if not pool or type(pool.GetCollectiblesFromPool) ~= "function" then
        stats.error = "missing_GetCollectiblesFromPool"
        return stats
    end

    local ok, poolItems = pcall(function()
        return pool:GetCollectiblesFromPool(stats.poolType)
    end)
    if not ok or type(poolItems) ~= "table" then
        stats.error = tostring(poolItems)
        return stats
    end

    stats.ok = true
    for _, poolItem in pairs(poolItems) do
        if type(poolItem) == "table" then
            local itemId = getPoolItemId(poolItem)
            local weight = tonumber(getPoolItemField(poolItem, "weight", "Weight", 3)) or 0
            local removeOn = tonumber(getPoolItemField(poolItem, "removeOn", "RemoveOn", 5)) or 0
            local isUnlocked = getPoolItemField(poolItem, "isUnlocked", "IsUnlocked", 6)
            stats.entries = stats.entries + 1
            stats.totalWeight = stats.totalWeight + weight
            if isUnlocked ~= false and weight > removeOn then
                stats.available = stats.available + 1
            end
            if itemId then
                local itemStats = stats.items[itemId] or {
                    entries = 0,
                    available = 0,
                    totalWeight = 0,
                    removeOn = removeOn,
                    unlocked = false,
                }
                itemStats.entries = itemStats.entries + 1
                itemStats.totalWeight = itemStats.totalWeight + weight
                itemStats.removeOn = math.max(tonumber(itemStats.removeOn) or 0, removeOn)
                if isUnlocked ~= false then
                    itemStats.unlocked = true
                end
                if isUnlocked ~= false and weight > removeOn then
                    itemStats.available = itemStats.available + 1
                end
                stats.items[itemId] = itemStats
            end
        end
    end

    stats.removedItems, stats.removedAll = copyRemovedCollectibles(pool)

    return stats
end

local function collectPoolTypesFromEntries(entries)
    local seen = {}
    local poolTypes = {}

    local function addPoolType(poolType)
        poolType = tonumber(poolType)
        if not poolType or poolType < 0 or seen[poolType] then
            return
        end

        seen[poolType] = true
        table.insert(poolTypes, poolType)
    end

    for _, entry in ipairs(entries or {}) do
        local cycleState = getPickupCycleState(entry.pickup)
        addPoolType(cycleState and cycleState.poolType)
    end
    addPoolType(getRoomPoolType())
    addPoolType(getLastPoolType())

    table.sort(poolTypes)
    return poolTypes
end

local function collectAllPoolTypes()
    local pool = Game():GetItemPool()
    if not pool or type(pool.GetNumItemPools) ~= "function" then
        return collectPoolTypesFromEntries({})
    end

    local ok, count = pcall(function()
        return pool:GetNumItemPools()
    end)
    if not ok or type(count) ~= "number" or count <= 0 then
        return collectPoolTypesFromEntries({})
    end

    local poolTypes = {}
    for poolType = 0, count - 1 do
        table.insert(poolTypes, poolType)
    end
    return poolTypes
end

local function capturePoolStats(poolTypes)
    local statsByPool = {}
    for _, poolType in ipairs(poolTypes or {}) do
        statsByPool[poolType] = getPoolStats(poolType)
    end
    return statsByPool
end

local function formatMaybeNumber(value, digits)
    if value == nil then
        return "n/a"
    end
    if digits then
        return string.format("%." .. tostring(digits) .. "f", value)
    end
    return tostring(value)
end

local function formatDelta(before, after, digits)
    if before == nil or after == nil then
        return "n/a"
    end

    local delta = after - before
    if digits then
        return string.format("%+." .. tostring(digits) .. "f", delta)
    end
    return string.format("%+d", delta)
end

local collectSortedIds
local writeIdChunks
local getUnexpectedItems

local function logPoolStatsDelta(label, beforeStats, afterStats, poolTypes, allowedItems)
    local function writeLog(text)
        local message = "[Severed Oath][Pool] " .. tostring(text)
        Isaac.DebugString(message)
        ConchBlessing.print(message)
    end

    local function logItemDiffs(poolType, before, after)
        local seen = {}
        local changed = {}
        local changedMap = {}

        for itemId in pairs(before.items or {}) do
            seen[itemId] = true
        end
        for itemId in pairs(after.items or {}) do
            seen[itemId] = true
        end
        for itemId in pairs(before.removedItems or {}) do
            seen[itemId] = true
        end
        for itemId in pairs(after.removedItems or {}) do
            seen[itemId] = true
        end

        for itemId in pairs(seen) do
            local beforeItem = before.items and before.items[itemId] or {}
            local afterItem = after.items and after.items[itemId] or {}
            local beforeRemoved = before.removedItems and before.removedItems[itemId] == true
            local afterRemoved = after.removedItems and after.removedItems[itemId] == true
            local beforeWeight = tonumber(beforeItem.totalWeight) or 0
            local afterWeight = tonumber(afterItem.totalWeight) or 0
            local beforeAvailable = tonumber(beforeItem.available) or 0
            local afterAvailable = tonumber(afterItem.available) or 0
            local beforeEntries = tonumber(beforeItem.entries) or 0
            local afterEntries = tonumber(afterItem.entries) or 0

            if beforeWeight ~= afterWeight
                or beforeAvailable ~= afterAvailable
                or beforeEntries ~= afterEntries
                or beforeRemoved ~= afterRemoved then
                table.insert(changed, {
                    itemId = itemId,
                    beforeWeight = beforeWeight,
                    afterWeight = afterWeight,
                    beforeAvailable = beforeAvailable,
                    afterAvailable = afterAvailable,
                    beforeEntries = beforeEntries,
                    afterEntries = afterEntries,
                    beforeRemoved = beforeRemoved,
                    afterRemoved = afterRemoved,
                })
                changedMap[itemId] = true
            end
        end

        table.sort(changed, function(left, right)
            return left.itemId < right.itemId
        end)

        if #changed <= 0 then
            writeLog(string.format("%s pool=%s item-diff none", tostring(label), tostring(poolType)))
            writeIdChunks(string.format("%s pool=%s item-diff unexpected count=0", tostring(label), tostring(poolType)), {})
            return
        end

        for _, diff in ipairs(changed) do
            writeLog(string.format(
                "%s pool=%s item-diff item=%s weight %s -> %s (%s), available %s -> %s (%s), entries %s -> %s (%s), removed %s -> %s",
                tostring(label),
                tostring(poolType),
                tostring(diff.itemId),
                formatMaybeNumber(diff.beforeWeight, 2),
                formatMaybeNumber(diff.afterWeight, 2),
                formatDelta(diff.beforeWeight, diff.afterWeight, 2),
                tostring(diff.beforeAvailable),
                tostring(diff.afterAvailable),
                formatDelta(diff.beforeAvailable, diff.afterAvailable),
                tostring(diff.beforeEntries),
                tostring(diff.afterEntries),
                formatDelta(diff.beforeEntries, diff.afterEntries),
                tostring(diff.beforeRemoved),
                tostring(diff.afterRemoved)
            ))
        end
        local unexpected = getUnexpectedItems(changedMap, allowedItems)
        writeIdChunks(string.format("%s pool=%s item-diff unexpected count=%d", tostring(label), tostring(poolType), #collectSortedIds(unexpected)), collectSortedIds(unexpected))
    end

    for _, poolType in ipairs(poolTypes or {}) do
        local before = beforeStats and beforeStats[poolType] or nil
        local after = afterStats and afterStats[poolType] or nil
        if not (before and after and before.ok and after.ok) then
            writeLog(string.format(
                "%s pool=%s unavailable before=%s after=%s",
                tostring(label),
                tostring(poolType),
                tostring(before and before.error),
                tostring(after and after.error)
            ))
        else
            writeLog(string.format(
                "%s pool=%s available %s -> %s (%s), entries %s -> %s (%s), weight %s -> %s (%s), removedAll %s -> %s (%s)",
                tostring(label),
                tostring(poolType),
                tostring(before.available),
                tostring(after.available),
                formatDelta(before.available, after.available),
                tostring(before.entries),
                tostring(after.entries),
                formatDelta(before.entries, after.entries),
                formatMaybeNumber(before.totalWeight, 2),
                formatMaybeNumber(after.totalWeight, 2),
                formatDelta(before.totalWeight, after.totalWeight, 2),
                formatMaybeNumber(before.removedAll),
                formatMaybeNumber(after.removedAll),
                formatDelta(before.removedAll, after.removedAll)
            ))
            logItemDiffs(poolType, before, after)
        end
    end
end

local function logVerify(text)
    local message = "[Severed Oath][Verify] " .. tostring(text)
    Isaac.DebugString(message)
    ConchBlessing.print(message)
end

local function writePoolDump(text)
    local message = "[Severed Oath][PoolDump] " .. tostring(text)
    Isaac.DebugString(message)
    ConchBlessing.print(message)
    Isaac.ConsoleOutput(message .. "\n")
end

local function writePoolTrack(text)
    local message = "[Severed Oath][PoolTrack] " .. tostring(text)
    Isaac.DebugString(message)
    ConchBlessing.print(message)
end

collectSortedIds = function(map)
    local ids = {}
    for itemId in pairs(map or {}) do
        table.insert(ids, tonumber(itemId) or itemId)
    end
    table.sort(ids, function(left, right)
        return tonumber(left) < tonumber(right)
    end)
    return ids
end

writeIdChunks = function(prefix, ids)
    ids = ids or {}
    if #ids <= 0 then
        writePoolTrack(prefix .. " []")
        return
    end

    local chunkSize = 80
    for startIndex = 1, #ids, chunkSize do
        local parts = {}
        local endIndex = math.min(startIndex + chunkSize - 1, #ids)
        for index = startIndex, endIndex do
            table.insert(parts, tostring(ids[index]))
        end
        writePoolTrack(string.format(
            "%s [%s] part=%d-%d/%d",
            prefix,
            table.concat(parts, ","),
            startIndex,
            endIndex,
            #ids
        ))
    end
end

local function getPoolExcludedItems(stats)
    local excluded = {}
    if not stats or not stats.ok then
        return excluded
    end

    for itemId, itemStats in pairs(stats.items or {}) do
        local removed = stats.removedItems and stats.removedItems[itemId] == true
        local available = tonumber(itemStats.available) or 0
        local weight = tonumber(itemStats.totalWeight) or 0
        local removeOn = tonumber(itemStats.removeOn) or 0
        local unlocked = itemStats.unlocked == true
        if removed or not unlocked or available <= 0 or weight <= removeOn then
            excluded[itemId] = true
        end
    end

    return excluded
end

local function diffIdMaps(beforeMap, afterMap)
    local added = {}
    local removed = {}

    for itemId in pairs(afterMap or {}) do
        if not (beforeMap and beforeMap[itemId]) then
            added[itemId] = true
        end
    end
    for itemId in pairs(beforeMap or {}) do
        if not (afterMap and afterMap[itemId]) then
            removed[itemId] = true
        end
    end

    return added, removed
end

local function collectPoolChangedItems(beforeStatsByPool, afterStatsByPool, poolTypes)
    local changed = {}

    for _, poolType in ipairs(poolTypes or {}) do
        local before = beforeStatsByPool and beforeStatsByPool[poolType] or nil
        local after = afterStatsByPool and afterStatsByPool[poolType] or nil
        if before and after and before.ok and after.ok then
            local seen = {}
            for itemId in pairs(before.items or {}) do
                seen[itemId] = true
            end
            for itemId in pairs(after.items or {}) do
                seen[itemId] = true
            end
            for itemId in pairs(before.removedItems or {}) do
                seen[itemId] = true
            end
            for itemId in pairs(after.removedItems or {}) do
                seen[itemId] = true
            end

            for itemId in pairs(seen) do
                local beforeItem = before.items and before.items[itemId] or {}
                local afterItem = after.items and after.items[itemId] or {}
                if (tonumber(beforeItem.totalWeight) or 0) ~= (tonumber(afterItem.totalWeight) or 0)
                    or (tonumber(beforeItem.available) or 0) ~= (tonumber(afterItem.available) or 0)
                    or (tonumber(beforeItem.entries) or 0) ~= (tonumber(afterItem.entries) or 0)
                    or ((before.removedItems and before.removedItems[itemId] == true) ~= (after.removedItems and after.removedItems[itemId] == true)) then
                    changed[itemId] = true
                end
            end
        end
    end

    return changed
end

local function makeItemSet(items)
    local set = {}
    for _, itemId in ipairs(items or {}) do
        itemId = tonumber(itemId)
        if itemId then
            set[itemId] = true
        end
    end
    return set
end

local function getEntryCycleItemSet(entries)
    local set = {}
    for _, entry in ipairs(entries or {}) do
        for _, itemId in ipairs(entry.cycleItems or {}) do
            itemId = tonumber(itemId)
            if itemId then
                set[itemId] = true
            end
        end
    end
    return set
end

getUnexpectedItems = function(items, allowedItems)
    local unexpected = {}
    allowedItems = allowedItems or {}
    for itemId in pairs(items or {}) do
        if not allowedItems[itemId] then
            unexpected[itemId] = true
        end
    end
    return unexpected
end

local function logPoolChangeValidation(label, beforeStatsByPool, afterStatsByPool, poolTypes, allowedItems)
    local changed = collectPoolChangedItems(beforeStatsByPool, afterStatsByPool, poolTypes)
    local unexpectedChanged = getUnexpectedItems(changed, allowedItems)
    writeIdChunks(string.format("%s changed count=%d", tostring(label), #collectSortedIds(changed)), collectSortedIds(changed))
    writeIdChunks(string.format("%s unexpected changed count=%d", tostring(label), #collectSortedIds(unexpectedChanged)), collectSortedIds(unexpectedChanged))

    local beforeAny = nil
    local afterAny = nil
    for _, poolType in ipairs(poolTypes or {}) do
        beforeAny = beforeAny or (beforeStatsByPool and beforeStatsByPool[poolType])
        afterAny = afterAny or (afterStatsByPool and afterStatsByPool[poolType])
    end
    local removedAdded = diffIdMaps(beforeAny and beforeAny.removedItems or {}, afterAny and afterAny.removedItems or {})
    local unexpectedRemoved = getUnexpectedItems(removedAdded, allowedItems)
    writeIdChunks(string.format("%s removed added count=%d", tostring(label), #collectSortedIds(removedAdded)), collectSortedIds(removedAdded))
    writeIdChunks(string.format("%s unexpected removed count=%d", tostring(label), #collectSortedIds(unexpectedRemoved)), collectSortedIds(unexpectedRemoved))

    local excludedAddedAll = {}
    for _, poolType in ipairs(poolTypes or {}) do
        local before = beforeStatsByPool and beforeStatsByPool[poolType] or nil
        local after = afterStatsByPool and afterStatsByPool[poolType] or nil
        if before and after and before.ok and after.ok then
            local excludedAdded = diffIdMaps(getPoolExcludedItems(before), getPoolExcludedItems(after))
            for itemId in pairs(excludedAdded) do
                excludedAddedAll[itemId] = true
            end
        end
    end
    local unexpectedExcluded = getUnexpectedItems(excludedAddedAll, allowedItems)
    writeIdChunks(string.format("%s excluded added count=%d", tostring(label), #collectSortedIds(excludedAddedAll)), collectSortedIds(excludedAddedAll))
    writeIdChunks(string.format("%s unexpected excluded count=%d", tostring(label), #collectSortedIds(unexpectedExcluded)), collectSortedIds(unexpectedExcluded))
end

local function logRemovedSnapshot(label, statsByPool, poolTypes)
    local pool = Game():GetItemPool()
    local removedItems, removedCount = copyRemovedCollectibles(pool)
    local removedIds = collectSortedIds(removedItems)
    writeIdChunks(string.format("%s removed-global count=%s", tostring(label), tostring(removedCount or #removedIds)), removedIds)

    for _, poolType in ipairs(poolTypes or {}) do
        local stats = statsByPool and statsByPool[poolType] or getPoolStats(poolType)
        if stats and stats.ok then
            local excludedIds = collectSortedIds(getPoolExcludedItems(stats))
            writeIdChunks(string.format("%s pool=%s excluded count=%d", tostring(label), tostring(poolType), #excludedIds), excludedIds)
        else
            writePoolTrack(string.format(
                "%s pool=%s excluded unavailable error=%s",
                tostring(label),
                tostring(poolType),
                tostring(stats and stats.error)
            ))
        end
    end
end

local function logRemovedDelta(label, beforeStatsByPool, afterStatsByPool, poolTypes, allowedItems)
    local beforeAny = nil
    local afterAny = nil
    for _, poolType in ipairs(poolTypes or {}) do
        beforeAny = beforeAny or (beforeStatsByPool and beforeStatsByPool[poolType])
        afterAny = afterAny or (afterStatsByPool and afterStatsByPool[poolType])
    end

    local beforeRemoved = beforeAny and beforeAny.removedItems or {}
    local afterRemoved = afterAny and afterAny.removedItems or {}
    local globalAdded, globalRestored = diffIdMaps(beforeRemoved, afterRemoved)
    writeIdChunks(string.format("%s removed-global added count=%d", tostring(label), #collectSortedIds(globalAdded)), collectSortedIds(globalAdded))
    writeIdChunks(string.format("%s removed-global unexpected count=%d", tostring(label), #collectSortedIds(getUnexpectedItems(globalAdded, allowedItems))), collectSortedIds(getUnexpectedItems(globalAdded, allowedItems)))
    writeIdChunks(string.format("%s removed-global restored count=%d", tostring(label), #collectSortedIds(globalRestored)), collectSortedIds(globalRestored))

    for _, poolType in ipairs(poolTypes or {}) do
        local before = beforeStatsByPool and beforeStatsByPool[poolType] or nil
        local after = afterStatsByPool and afterStatsByPool[poolType] or nil
        if before and after and before.ok and after.ok then
            local excludedAdded, excludedRestored = diffIdMaps(getPoolExcludedItems(before), getPoolExcludedItems(after))
            writeIdChunks(string.format("%s pool=%s excluded added count=%d", tostring(label), tostring(poolType), #collectSortedIds(excludedAdded)), collectSortedIds(excludedAdded))
            writeIdChunks(string.format("%s pool=%s excluded unexpected count=%d", tostring(label), tostring(poolType), #collectSortedIds(getUnexpectedItems(excludedAdded, allowedItems))), collectSortedIds(getUnexpectedItems(excludedAdded, allowedItems)))
            writeIdChunks(string.format("%s pool=%s excluded restored count=%d", tostring(label), tostring(poolType), #collectSortedIds(excludedRestored)), collectSortedIds(excludedRestored))
        else
            writePoolTrack(string.format(
                "%s pool=%s excluded-diff unavailable before=%s after=%s",
                tostring(label),
                tostring(poolType),
                tostring(before and before.error),
                tostring(after and after.error)
            ))
        end
    end
end

local function parseCommandParams(params)
    local args = {}
    for part in tostring(params or ""):gmatch("%S+") do
        table.insert(args, part)
    end
    return args
end

local function dumpPoolItem(poolType, itemId)
    local stats = getPoolStats(poolType)
    if not stats.ok then
        writePoolDump(string.format("pool=%s unavailable error=%s", tostring(poolType), tostring(stats.error)))
        return
    end

    local itemStats = stats.items[tonumber(itemId)] or {}
    local removed = stats.removedItems and stats.removedItems[tonumber(itemId)] == true
    writePoolDump(string.format(
        "pool=%s item=%s weight=%s available=%s entries=%s removed=%s",
        tostring(poolType),
        tostring(itemId),
        formatMaybeNumber(tonumber(itemStats.totalWeight) or 0, 2),
        tostring(tonumber(itemStats.available) or 0),
        tostring(tonumber(itemStats.entries) or 0),
        tostring(removed)
    ))
end

local function dumpPool(poolType, dumpAll)
    local stats = getPoolStats(poolType)
    if not stats.ok then
        writePoolDump(string.format("pool=%s unavailable error=%s", tostring(poolType), tostring(stats.error)))
        return
    end

    writePoolDump(string.format(
        "pool=%s available=%s entries=%s weight=%s removedAll=%s",
        tostring(poolType),
        tostring(stats.available),
        tostring(stats.entries),
        formatMaybeNumber(stats.totalWeight, 2),
        formatMaybeNumber(stats.removedAll)
    ))

    local items = {}
    for itemId, itemStats in pairs(stats.items or {}) do
        table.insert(items, {
            itemId = itemId,
            totalWeight = tonumber(itemStats.totalWeight) or 0,
            available = tonumber(itemStats.available) or 0,
            entries = tonumber(itemStats.entries) or 0,
            removed = stats.removedItems and stats.removedItems[itemId] == true,
        })
    end
    table.sort(items, function(left, right)
        return left.itemId < right.itemId
    end)

    local limit = dumpAll and #items or math.min(#items, 40)
    for index = 1, limit do
        local itemStats = items[index]
        writePoolDump(string.format(
            "pool=%s item=%s weight=%s available=%s entries=%s removed=%s",
            tostring(poolType),
            tostring(itemStats.itemId),
            formatMaybeNumber(itemStats.totalWeight, 2),
            tostring(itemStats.available),
            tostring(itemStats.entries),
            tostring(itemStats.removed)
        ))
    end

    if not dumpAll and #items > limit then
        writePoolDump(string.format("pool=%s omitted=%s use 'cb_pool %s all' for full dump", tostring(poolType), tostring(#items - limit), tostring(poolType)))
    end
end

local function queueDelayedPoolCheck(label, beforeStats, poolTypes, delayFrames, allowedItems)
    table.insert(M._pendingPoolChecks, {
        label = label,
        beforeStats = beforeStats,
        poolTypes = poolTypes,
        allowedItems = allowedItems,
        targetFrame = Game():GetFrameCount() + (tonumber(delayFrames) or 1),
    })
end

local function processPendingPoolChecks()
    if #M._pendingPoolChecks <= 0 then
        return
    end

    local frame = Game():GetFrameCount()
    for index = #M._pendingPoolChecks, 1, -1 do
        local check = M._pendingPoolChecks[index]
        if frame >= (tonumber(check.targetFrame) or frame) then
            local afterStats = capturePoolStats(check.poolTypes)
            logPoolStatsDelta(check.label, check.beforeStats, afterStats, check.poolTypes, check.allowedItems)
            logRemovedDelta(check.label, check.beforeStats, afterStats, check.poolTypes, check.allowedItems)
            table.remove(M._pendingPoolChecks, index)
        end
    end
end

local function playerHoldsSeveredOath(player)
    if not player or not SEVERED_OATH_ID or SEVERED_OATH_ID <= 0 then
        return false
    end

    if type(player.GetActiveItem) == "function" then
        for _, slot in ipairs(ACTIVE_SLOTS) do
            local ok, itemId = pcall(function()
                return player:GetActiveItem(slot)
            end)
            if ok and itemId == SEVERED_OATH_ID then
                return true
            end
        end
    end

    return type(player.HasCollectible) == "function" and player:HasCollectible(SEVERED_OATH_ID)
end

local function anyoneHoldsSeveredOath()
    local game = Game()
    for i = 0, game:GetNumPlayers() - 1 do
        local player = game:GetPlayer(i)
        if playerHoldsSeveredOath(player) then
            return true
        end
    end
    return false
end

local function anyoneHasCycleModifier()
    local game = Game()
    for i = 0, game:GetNumPlayers() - 1 do
        local player = game:GetPlayer(i)
        if player and type(player.HasCollectible) == "function" then
            for _, itemId in ipairs(CYCLE_MODIFIER_ITEMS) do
                if itemId and itemId > 0 and player:HasCollectible(itemId) then
                    return true
                end
            end
        end
    end
    return false
end

local function getExtraCycleItem(pickup, data, excludedItems)
    local pool = Game():GetItemPool()
    if not pool then
        return nil
    end

    local poolType = tonumber(data and data[CYCLE_POOL_MARKER]) or getRoomPoolType()
    local seed = tonumber(pickup and pickup.InitSeed) or Game():GetFrameCount()
    local defaultItem = (CollectibleType and (CollectibleType.COLLECTIBLE_NULL or CollectibleType.NULL)) or 0
    excludedItems = excludedItems or {}

    for attempt = 1, EXTRA_CYCLE_PICK_ATTEMPTS do
        local pickSeed = seed + 7919 + ((attempt - 1) * 104729)
        local previewOk, previewItem = pcall(function()
            return pool:GetCollectible(poolType, false, pickSeed, defaultItem)
        end)
        if not previewOk then
            logVerify(string.format(
                "bonus-cycle-preview failed pool=%s ok=%s seed=%s",
                tostring(poolType),
                tostring(previewOk),
                tostring(pickSeed)
            ))
            return nil
        end

        if isValidCollectibleId(previewItem) then
            if excludedItems[previewItem] then
                logVerify(string.format(
                    "bonus-cycle-preview skip duplicate pool=%s item=%s seed=%s attempt=%d",
                    tostring(poolType),
                    tostring(previewItem),
                    tostring(pickSeed),
                    attempt
                ))
            else
                local poolTypes = collectAllPoolTypes()
                local beforePoolStats = capturePoolStats(poolTypes)
                local ok, itemId = pcall(function()
                    return pool:GetCollectible(poolType, true, pickSeed, defaultItem)
                end)
                local afterPoolStats = capturePoolStats(poolTypes)

                if ok and isValidCollectibleId(itemId) then
                    logVerify(string.format(
                        "bonus-cycle-create pool=%s item=%s preview=%s seed=%s attempt=%d",
                        tostring(poolType),
                        tostring(itemId),
                        tostring(previewItem),
                        tostring(pickSeed),
                        attempt
                    ))
                    logPoolChangeValidation(
                        "bonus-cycle-create",
                        beforePoolStats,
                        afterPoolStats,
                        poolTypes,
                        makeItemSet({ itemId })
                    )
                    if excludedItems[itemId] then
                        logVerify(string.format(
                            "bonus-cycle-create rejected duplicate-after-decrease pool=%s item=%s seed=%s",
                            tostring(poolType),
                            tostring(itemId),
                            tostring(pickSeed)
                        ))
                        return nil
                    end
                    return itemId
                end

                logVerify(string.format(
                    "bonus-cycle-create failed pool=%s item=%s ok=%s seed=%s attempt=%d",
                    tostring(poolType),
                    tostring(itemId),
                    tostring(ok),
                    tostring(pickSeed),
                    attempt
                ))
                logPoolChangeValidation(
                    "bonus-cycle-create-failed",
                    beforePoolStats,
                    afterPoolStats,
                    poolTypes,
                    {}
                )
                return nil
            end
        end
    end

    logVerify(string.format(
        "bonus-cycle-create no non-duplicate candidate pool=%s seed=%s attempts=%d",
        tostring(poolType),
        tostring(seed),
        EXTRA_CYCLE_PICK_ATTEMPTS
    ))
    return nil
end

local finishHeldBonusCycle

local function markPickupCycleState(pickup)
    if not pickup or pickup.Variant ~= PickupVariant.PICKUP_COLLECTIBLE then
        return
    end

    local existingState = getPickupCycleState(pickup)
    if existingState then
        local currentItem = tonumber(pickup.SubType)
        local stateSplitItem = tonumber(existingState.splitItem)
        if not stateSplitItem and existingState.eligible == false and existingState.done == true then
            local data = pickup:GetData()
            stateSplitItem = tonumber(data[SPLIT_ITEM_MARKER]) or getSavedSplitItem(pickup)
            existingState.splitItem = stateSplitItem
        end
        local stateItem = tonumber(existingState.item)
        if not stateSplitItem and existingState.eligible == false and stateItem and stateItem ~= currentItem and anyoneHoldsSeveredOath() then
            local key = getPickupCycleKey(pickup)
            if key then
                M._cyclePickupStates[key] = nil
            end
            logVerify(string.format(
                "cycle-resume rerolled newly eligible seed=%s subtype=%s oldItem=%s",
                tostring(pickup.InitSeed),
                tostring(pickup.SubType),
                tostring(stateItem)
            ))
        elseif stateSplitItem and stateSplitItem ~= currentItem then
            local key = getPickupCycleKey(pickup)
            if key then
                M._cyclePickupStates[key] = nil
            end
            local data = pickup:GetData()
            data[SPLIT_MARKER] = nil
            data[SPLIT_ITEM_MARKER] = nil
            clearSavedSplitPickup(pickup)
            logVerify(string.format(
                "cycle-resume rerolled split-state seed=%s subtype=%s oldSplitItem=%s",
                tostring(pickup.InitSeed),
                tostring(pickup.SubType),
                tostring(stateSplitItem)
            ))
        else
            updateBonusSeen(pickup, existingState)
            writeCycleStateToPickup(pickup, existingState)
            if existingState.eligible and not existingState.done and finishHeldBonusCycle then
                finishHeldBonusCycle(pickup, existingState)
            end
            return
        end
    end

    local data = pickup:GetData()
    local currentItem = tonumber(pickup.SubType)
    local dataSplitItem = tonumber(data[SPLIT_ITEM_MARKER])
    local savedSplitItem = getSavedSplitItem(pickup)
    local dataMatchesSplitItem = data[SPLIT_MARKER] == true and dataSplitItem ~= nil and dataSplitItem == currentItem
    local saveMatchesSplitItem = savedSplitItem ~= nil and savedSplitItem == currentItem
    if dataMatchesSplitItem or saveMatchesSplitItem then
        setPickupCycleState(pickup, {
            eligible = false,
            done = true,
            initFrame = Game():GetFrameCount(),
            poolType = getLastPoolType(),
            item = currentItem,
            splitItem = currentItem,
        })
        logVerify(string.format(
            "cycle-skip split item seed=%s subtype=%s splitItem=%s",
            tostring(pickup.InitSeed),
            tostring(pickup.SubType),
            tostring(dataSplitItem or savedSplitItem)
        ))
        return
    end
    if data[SPLIT_MARKER] or savedSplitItem ~= nil then
        data[SPLIT_MARKER] = nil
        data[SPLIT_ITEM_MARKER] = nil
        clearSavedSplitPickup(pickup)
        logVerify(string.format(
            "cycle-resume rerolled split seed=%s subtype=%s oldSplitItem=%s",
            tostring(pickup.InitSeed),
            tostring(pickup.SubType),
            tostring(dataSplitItem or savedSplitItem)
        ))
    end

    local savedBonusState = getSavedBonusState(pickup)
    if type(savedBonusState) == "table" and isValidCollectibleId(savedBonusState.bonusItem) then
        local state = {
            eligible = true,
            done = true,
            initFrame = Game():GetFrameCount(),
            poolType = tonumber(savedBonusState.poolType) or getLastPoolType(),
            item = currentItem,
            bonusItem = tonumber(savedBonusState.bonusItem),
            bonusSeen = savedBonusState.bonusSeen == true,
        }
        setPickupCycleState(pickup, state)
        updateBonusSeen(pickup, state)
        logVerify(string.format(
            "cycle-skip saved bonus seed=%s subtype=%s bonus=%s seen=%s raw=%d",
            tostring(pickup.InitSeed),
            tostring(pickup.SubType),
            tostring(state.bonusItem),
            tostring(state.bonusSeen),
            #getRawCycleItems(pickup)
        ))
        return
    end

    if isContinuedPickupLoadFrame() then
        setPickupCycleState(pickup, {
            eligible = false,
            done = true,
            initFrame = Game():GetFrameCount(),
            poolType = getLastPoolType(),
            item = currentItem,
        })
        logVerify(string.format(
            "cycle-skip continued load seed=%s subtype=%s raw=%d",
            tostring(pickup.InitSeed),
            tostring(pickup.SubType),
            #getRawCycleItems(pickup)
        ))
        return
    end

    local eligible = anyoneHoldsSeveredOath()
    local state = {
        eligible = eligible,
        done = not eligible,
        initFrame = Game():GetFrameCount(),
        poolType = getLastPoolType(),
        item = currentItem,
        bonusItem = nil,
        bonusSeen = false,
    }
    setPickupCycleState(pickup, state)
    if state.eligible and finishHeldBonusCycle then
        finishHeldBonusCycle(pickup, state)
    end
end

local function addHeldBonusCycle(pickup, data)
    if not pickup or pickup.Variant ~= PickupVariant.PICKUP_COLLECTIBLE then
        return false, "invalid_pickup"
    end
    if not isValidCollectibleId(pickup.SubType) then
        return false, "invalid_subtype"
    end
    if type(pickup.GetCollectibleCycle) ~= "function" then
        return false, "missing_repentogon"
    end

    local rawCycleItems = getRawCycleItems(pickup)
    local age = Game():GetFrameCount() - (tonumber(data and data[CYCLE_INIT_FRAME_MARKER]) or 0)
    if #rawCycleItems <= 0 and anyoneHasCycleModifier() and age < 3 then
        return nil, "waiting_for_native_cycle"
    end

    if type(pickup.AddCollectibleCycle) ~= "function" then
        return false, "missing_add_cycle"
    end
    if #rawCycleItems >= MAX_COLLECTIBLE_CYCLE_ITEMS then
        return false, "cycle_full"
    end

    local existingCycleItems = getCycleItems(pickup)
    local extraItem = getExtraCycleItem(pickup, data, makeItemSet(existingCycleItems))
    if not extraItem then
        return false, "no_pool_item"
    end

    local ok, added = pcall(function()
        return pickup:AddCollectibleCycle(extraItem)
    end)
    if ok and added ~= false then
        return true, extraItem
    end

    return false, "add_failed"
end

finishHeldBonusCycle = function(pickup, state)
    if not pickup or not state or state.done then
        return
    end

    state.done = true
    writeCycleStateToPickup(pickup, state)

    local data = pickup:GetData()
    local added, detail = addHeldBonusCycle(pickup, data)
    if added == nil then
        state.done = false
        writeCycleStateToPickup(pickup, state)
        return
    end

    writeCycleStateToPickup(pickup, state)
    if added and type(detail) == "number" then
        state.bonusItem = detail
        state.bonusSeen = pickup.SubType == detail
        writeCycleStateToPickup(pickup, state)
        updateBonusSeen(pickup, state)
        markSavedBonusState(pickup, state)
    end
    if added then
        ConchBlessing.printDebug(string.format(
            "[Severed Oath] Added bonus cycle item to pickup %d (%s, seed=%s).",
            pickup.SubType,
            tostring(detail),
            tostring(pickup.InitSeed)
        ))
    else
        ConchBlessing.printDebug(string.format(
            "[Severed Oath] Skipped bonus cycle for pickup %d: %s (seed=%s).",
            pickup.SubType,
            tostring(detail),
            tostring(pickup.InitSeed)
        ))
    end
end

local function getSplitCycleItems(pickup)
    local items = getCycleItems(pickup)
    local state = getPickupCycleState(pickup)
    updateBonusSeen(pickup, state)
    return items
end

local function spawnCleaverSlashEffect(pos, player)
    if not pos then
        return
    end

    local variant = EffectVariant.CLEAVER_SLASH
        or EffectVariant.SCYTHE_BREAK
        or EffectVariant.POOF01
        or EffectVariant.POOF_1
        or 15
    Isaac.Spawn(EntityType.ENTITY_EFFECT, variant, 0, pos, Vector.Zero, player)
end

local function savePickupState(pickup)
    return {
        charge = pickup.Charge,
        price = pickup.Price,
        shopItemId = pickup.ShopItemId,
        timeout = pickup.Timeout,
        wait = pickup.Wait,
    }
end

local function applyPickupState(pickup, state, optionsPickupIndex)
    if not pickup or not state then
        return
    end

    pickup.OptionsPickupIndex = tonumber(optionsPickupIndex) or 0
    if state.price ~= nil then
        pickup.Price = state.price
    end
    if state.timeout ~= nil then
        pickup.Timeout = state.timeout
    end
    if state.charge ~= nil then
        pickup.Charge = state.charge
    end
    if pickup.AutoUpdatePrice ~= nil then
        pickup.AutoUpdatePrice = false
    end

    local wait = tonumber(state.wait) or 0
    pickup.Wait = math.max(wait, MIN_PICKUP_WAIT)

    local shopItemId = tonumber(state.shopItemId)
    if shopItemId and shopItemId < 0 then
        pickup.ShopItemId = shopItemId
    else
        pickup.ShopItemId = -1
    end

    pickup.Touched = false
end

local function getSplitPosition(room, basePos, index, count)
    local centeredIndex = index - ((count + 1) / 2)
    local target = basePos + Vector(centeredIndex * SPLIT_SPACING, 0)
    local ok, pos = pcall(function()
        return room:FindFreePickupSpawnPosition(target, 0, true)
    end)
    if ok and pos then
        return pos
    end
    return target
end

local function spawnSplitPickup(itemId, pos, state, player, optionsPickupIndex)
    -- Spawn as a non-collectible first so Glitched Crown/Birthright/Binge Eater
    -- do not initialize a fresh cycle and consume extra pool entries.
    local entity = Isaac.Spawn(
        EntityType.ENTITY_PICKUP,
        PickupVariant.PICKUP_COIN,
        (CoinSubType and CoinSubType.COIN_PENNY) or 1,
        pos,
        Vector.Zero,
        player
    )
    local pickup = entity and entity:ToPickup() or nil
    if not pickup then
        return nil
    end

    local data = pickup:GetData()
    data[SPLIT_MARKER] = true
    data[SPLIT_ITEM_MARKER] = itemId
    data[CYCLE_DONE_MARKER] = true

    local ok = pcall(function()
        pickup:Morph(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_COLLECTIBLE, itemId, true, true, true)
    end)
    if not ok or pickup.Variant ~= PickupVariant.PICKUP_COLLECTIBLE then
        pickup:Remove()
        return nil
    end
    if type(pickup.RemoveCollectibleCycle) == "function" then
        pcall(function()
            pickup:RemoveCollectibleCycle()
        end)
    end

    applyPickupState(pickup, state, optionsPickupIndex)
    setPickupCycleState(pickup, {
        eligible = false,
        done = true,
        initFrame = Game():GetFrameCount(),
        poolType = getLastPoolType(),
        item = itemId,
        splitItem = itemId,
    })
    markSavedSplitPickup(pickup, itemId)
    return pickup
end

local function splitPickup(entry, player)
    local pickup = entry.pickup
    local cycleItems = entry.cycleItems
    local room = Game():GetRoom()
    local basePos = entry.basePos
    local state = entry.state
    local count = #cycleItems

    spawnCleaverSlashEffect(basePos, player)
    ConchBlessing.printDebug(string.format(
        "[Severed Oath] Spawning split items from seed=%s items=[%s].",
        tostring(pickup.InitSeed),
        formatItemList(cycleItems)
    ))
    pickup:Remove()

    for index, itemId in ipairs(cycleItems) do
        local pos = getSplitPosition(room, basePos, index, count)
        local optionsPickupIndex = entry.splitOptions and entry.splitOptions[index] or 0
        spawnSplitPickup(itemId, pos, state, player, optionsPickupIndex)
    end

    return count
end

local function collectSplitEntries()
    local entries = {}
    local maxOptionsPickupIndex = 0

    for _, entity in ipairs(Isaac.GetRoomEntities()) do
        if entity.Type == EntityType.ENTITY_PICKUP
            and entity.Variant == PickupVariant.PICKUP_COLLECTIBLE then
            local pickup = entity:ToPickup()
            if pickup and pickup:Exists() then
                markPickupCycleState(pickup)
                if not pickup:GetData()[SPLIT_MARKER] then

                    local optionsPickupIndex = getPickupOptionsIndex(pickup)
                    maxOptionsPickupIndex = math.max(maxOptionsPickupIndex, optionsPickupIndex)

                    local rawCycleValues = getCollectibleCycleValues(pickup)
                    local rawCycleItems = getCycleItems(pickup)
                    local cycleItems = getSplitCycleItems(pickup)
                    local state = getPickupCycleState(pickup)
                    if #rawCycleItems > 1 or (state and state.bonusItem) then
                        logVerify(string.format(
                            "split-check seed=%s subtype=%s options=%s cycleRaw=[%s] unique=[%s] split=[%s] bonus=%s seen=%s",
                            tostring(pickup.InitSeed),
                            tostring(pickup.SubType),
                            tostring(optionsPickupIndex),
                            formatItemList(rawCycleValues),
                            formatItemList(rawCycleItems),
                            formatItemList(cycleItems),
                            tostring(state and state.bonusItem),
                            tostring(state and state.bonusSeen)
                        ))
                    end
                    if #cycleItems > 1 then
                        table.insert(entries, {
                            pickup = pickup,
                            basePos = pickup.Position,
                            cycleItems = cycleItems,
                            optionsPickupIndex = optionsPickupIndex,
                            state = savePickupState(pickup),
                            splitOptions = {},
                        })
                    end
                end
            end
        end
    end

    return entries, maxOptionsPickupIndex
end

local function assignSplitOptions(entries, firstFreeOptionsPickupIndex)
    local optionGroups = {}
    for _, entry in ipairs(entries) do
        if entry.optionsPickupIndex > 0 then
            local key = entry.optionsPickupIndex
            optionGroups[key] = optionGroups[key] or {}
            table.insert(optionGroups[key], entry)
        end
    end

    local nextOptionsPickupIndex = firstFreeOptionsPickupIndex
    for _, group in pairs(optionGroups) do
        if #group > 1 then
            local maxCycleCount = 0
            for _, entry in ipairs(group) do
                maxCycleCount = math.max(maxCycleCount, #entry.cycleItems)
            end

            for cycleIndex = 1, maxCycleCount do
                local linkedCount = 0
                for _, entry in ipairs(group) do
                    if entry.cycleItems[cycleIndex] then
                        linkedCount = linkedCount + 1
                    end
                end

                if linkedCount > 1 then
                    for _, entry in ipairs(group) do
                        if entry.cycleItems[cycleIndex] then
                            entry.splitOptions[cycleIndex] = nextOptionsPickupIndex
                        end
                    end
                    nextOptionsPickupIndex = nextOptionsPickupIndex + 1
                end
            end
        end
    end
end

local function splitRoomCycles(player)
    local splitCount = 0
    local spawnedCount = 0
    local entries, maxOptionsPickupIndex = collectSplitEntries()
    local poolTypes = collectAllPoolTypes()
    local visibleItems = getEntryCycleItemSet(entries)
    local beforePoolStats = capturePoolStats(poolTypes)
    logVerify(string.format("active-before entries=%d pools=all(%d) visible=[%s]", #entries, #poolTypes, formatItemList(collectSortedIds(visibleItems))))
    assignSplitOptions(entries, maxOptionsPickupIndex + 1)

    for _, entry in ipairs(entries) do
        if entry.pickup and entry.pickup:Exists() then
            local count = splitPickup(entry, player)
            splitCount = splitCount + 1
            spawnedCount = spawnedCount + count
        end
    end

    local afterPoolStats = capturePoolStats(poolTypes)
    if splitCount > 0 then
        logPoolStatsDelta("after-active", beforePoolStats, afterPoolStats, poolTypes, visibleItems)
        logRemovedDelta("after-active", beforePoolStats, afterPoolStats, poolTypes, visibleItems)
        queueDelayedPoolCheck("after-active+2f", beforePoolStats, poolTypes, 2, visibleItems)
    else
        logVerify("active-after no split targets")
        logRemovedDelta("after-active", beforePoolStats, afterPoolStats, poolTypes, visibleItems)
    end

    return splitCount, spawnedCount
end

function M.onUseItem(_, collectibleId, rng, player, useFlags, activeSlot, varData)
    if collectibleId ~= SEVERED_OATH_ID then
        return
    end

    if not player or not player.Position then
        player = Isaac.GetPlayer(0)
    end

    local splitCount, spawnedCount = splitRoomCycles(player)
    if splitCount <= 0 then
        logVerify("active-result no cycling collectible pickups found")
        ConchBlessing.printDebug("[Severed Oath] No cycling collectible pickups found.")
        return { Discharge = false, Remove = false, ShowAnim = false }
    end

    SFXManager():Play(SoundEffect.SOUND_POWERUP_SPEWER, 1.0, 0, false, 1.0, 0)
    logVerify(string.format("active-result split=%d spawned=%d", splitCount, spawnedCount))
    ConchBlessing.printDebug(string.format("[Severed Oath] Split %d cycling pickups into %d items.", splitCount, spawnedCount))
    return { Discharge = true, Remove = false, ShowAnim = true }
end

function M.onPostPickupInit(_, pickup)
    markPickupCycleState(pickup)
end

function M.onPostPickupUpdate(_, pickup)
    if not pickup or pickup.Variant ~= PickupVariant.PICKUP_COLLECTIBLE then
        return
    end

    markPickupCycleState(pickup)
    local state = getPickupCycleState(pickup)
    if not state then
        return
    end
    updateBonusSeen(pickup, state)
    writeCycleStateToPickup(pickup, state)

    if state.done then
        return
    end
    if pickup:GetData()[SPLIT_MARKER] then
        state.done = true
        writeCycleStateToPickup(pickup, state)
        return
    end
    if not state.eligible then
        state.done = true
        writeCycleStateToPickup(pickup, state)
        return
    end
    if Game():GetFrameCount() <= (tonumber(state.initFrame) or 0) then
        return
    end

    finishHeldBonusCycle(pickup, state)
end

function M.onGameStarted(_, isContinued)
    M._cyclePickupStates = {}
    M._cycleRoomKey = nil
    M._cycleRoomLoadFrame = Game():GetFrameCount()
    M._pendingPoolChecks = {}
    M._continuedRun = isContinued == true
    if isContinued then
        M._suppressContinuedPickupCyclesUntil = Game():GetFrameCount() + CONTINUED_PICKUP_LOAD_SUPPRESS_FRAMES
    else
        M._suppressContinuedPickupCyclesUntil = nil
    end
    logVerify(string.format(
        "game-start continued=%s suppressUntil=%s",
        tostring(isContinued == true),
        tostring(M._suppressContinuedPickupCyclesUntil)
    ))

    local poolTypes = collectPoolTypesFromEntries({})
    logRemovedSnapshot("game-start", capturePoolStats(poolTypes), poolTypes)
end

function M.onPostNewRoom()
    ensureCycleRoomState()
    if M._continuedRun == true and not Game():GetRoom():IsFirstVisit() then
        logVerify(string.format(
            "continued revisit room load frame=%s suppressUntil=%s",
            tostring(M._cycleRoomLoadFrame),
            tostring((tonumber(M._cycleRoomLoadFrame) or 0) + CONTINUED_PICKUP_LOAD_SUPPRESS_FRAMES)
        ))
    end
end

function M.onExecuteCmd(_, command, params)
    if command == "cb_removed" or command == "cb_excluded" then
        local args = parseCommandParams(params)
        local poolTypes
        if args[1] == "all" then
            poolTypes = collectAllPoolTypes()
        else
            local poolType = tonumber(args[1]) or getRoomPoolType()
            poolTypes = { poolType }
        end
        logRemovedSnapshot("cmd", capturePoolStats(poolTypes), poolTypes)
        return
    end

    if command ~= "cb_pool" and command ~= "cb_pooldump" then
        return
    end

    local args = parseCommandParams(params)
    local poolType = tonumber(args[1]) or getRoomPoolType()
    local secondArg = args[2]
    if secondArg and secondArg ~= "all" then
        local itemId = tonumber(secondArg)
        if itemId then
            dumpPoolItem(poolType, itemId)
            return
        end
    end

    dumpPool(poolType, secondArg == "all" or args[1] == "all")
end

function M.onBeforeChange(upgradePos, pickup, _)
    return ConchBlessing.template.positive.onBeforeChange(upgradePos, pickup, M.data)
end

function M.onAfterChange(upgradePos, pickup, _)
    ConchBlessing.template.positive.onAfterChange(upgradePos, pickup, M.data)
end

function M.onUpdate()
    ensureCycleRoomState()
    processPendingPoolChecks()
    ConchBlessing.template.onUpdate(M.data)
end
