local game = Game()
local DamageUtils = ConchBlessing.DamageUtils or require("scripts.lib.damage_utils")

ConchBlessing.twofacedpenny = {}

local M = ConchBlessing.twofacedpenny
local TWO_FACED_PENNY_ID = Isaac.GetItemIdByName("Two Faced Penny")
local HAS_POST_ADD_COLLECTIBLE = ModCallbacks and ModCallbacks.MC_POST_ADD_COLLECTIBLE ~= nil

local collectibleScanIds = nil

local function getFloorKey()
    local level = game:GetLevel()
    local stage = level:GetStage()
    local stageType = level:GetStageType()
    return tostring(stage) .. ":" .. tostring(stageType)
end

local function getPlayerData(player)
    local data = player:GetData()
    if not data.__twofacedpenny then
        data.__twofacedpenny = {
            tookDamageThisFloor = false,
            currentFloorKey = nil,
            lastPennyCount = nil,
            lastCollectibleCounts = nil,
            suppress = {},
            slots = {},
        }
    end
    return data.__twofacedpenny
end

local function isValidCollectibleId(itemId)
    return type(itemId) == "number" and itemId > 0
end

local function getPennyCount(player)
    if not player or not isValidCollectibleId(TWO_FACED_PENNY_ID) then
        return 0
    end

    local ok, count = pcall(function()
        return player:GetCollectibleNum(TWO_FACED_PENNY_ID, true)
    end)
    if ok and type(count) == "number" then
        return count
    end
    return 0
end

local function addScanId(ids, seen, itemId)
    itemId = tonumber(itemId)
    if not isValidCollectibleId(itemId) or seen[itemId] then
        return
    end

    seen[itemId] = true
    table.insert(ids, itemId)
end

local function getCollectibleScanIds()
    if collectibleScanIds then
        return collectibleScanIds
    end

    local ids = {}
    local seen = {}
    local maxId = CollectibleType.NUM_COLLECTIBLES or 0
    for itemId = 1, math.max(0, maxId - 1) do
        addScanId(ids, seen, itemId)
    end

    for _, itemData in pairs(ConchBlessing.ItemData or {}) do
        addScanId(ids, seen, itemData and itemData.id)
    end

    table.sort(ids)
    collectibleScanIds = ids
    return collectibleScanIds
end

local function buildCollectibleCounts(player)
    local counts = {}
    for _, itemId in ipairs(getCollectibleScanIds()) do
        local ok, count = pcall(function()
            return player:GetCollectibleNum(itemId, true)
        end)
        if ok and type(count) == "number" then
            counts[itemId] = count
        end
    end
    return counts
end

local function refreshCounts(player, pData)
    pData.lastCollectibleCounts = buildCollectibleCounts(player)
end

local function recordCollectibleCount(player, pData, itemId)
    if not isValidCollectibleId(itemId) then
        return
    end

    pData.lastCollectibleCounts = pData.lastCollectibleCounts or {}
    local ok, count = pcall(function()
        return player:GetCollectibleNum(itemId, true)
    end)
    if ok and type(count) == "number" then
        pData.lastCollectibleCounts[itemId] = count
    end
end

local function detectNewCollectibles(player, pData)
    if not pData.lastCollectibleCounts then
        refreshCounts(player, pData)
        return {}
    end

    local changes = {}
    local counts = pData.lastCollectibleCounts
    for _, itemId in ipairs(getCollectibleScanIds()) do
        local ok, current = pcall(function()
            return player:GetCollectibleNum(itemId, true)
        end)
        if ok and type(current) == "number" then
            local previous = counts[itemId] or 0
            if current > previous and itemId ~= TWO_FACED_PENNY_ID then
                table.insert(changes, {
                    itemId = itemId,
                    delta = current - previous,
                })
            end
            counts[itemId] = current
        end
    end

    return changes
end

local function syncPennySlots(player, pData)
    local pennyCount = getPennyCount(player)
    pData.slots = pData.slots or {}

    if pData.lastPennyCount == nil then
        pData.lastPennyCount = pennyCount
        return pennyCount
    end

    local previous = tonumber(pData.lastPennyCount) or 0
    if pennyCount > previous then
        for _ = 1, pennyCount - previous do
            table.insert(pData.slots, { itemId = nil, doubled = false })
        end
    elseif pennyCount < previous then
        while #pData.slots > pennyCount do
            table.remove(pData.slots)
        end
    end

    pData.lastPennyCount = pennyCount
    return pennyCount
end

local function consumeSuppressedAdd(pData, itemId, count)
    local suppress = pData.suppress
    if not suppress or not suppress[itemId] or suppress[itemId] <= 0 then
        return 0
    end

    local skipped = math.min(suppress[itemId], count or 1)
    suppress[itemId] = suppress[itemId] - skipped
    if suppress[itemId] <= 0 then
        suppress[itemId] = nil
    end
    return skipped
end

local function grantItem(player, itemId, count, pData)
    count = tonumber(count) or 0
    if count <= 0 or not isValidCollectibleId(itemId) then
        return
    end

    pData.suppress = pData.suppress or {}
    pData.suppress[itemId] = (pData.suppress[itemId] or 0) + count
    for _ = 1, count do
        player:AddCollectible(itemId, 0, true)
    end
end

local function claimNextCollectible(player, pData, itemId)
    if not isValidCollectibleId(itemId) or itemId == TWO_FACED_PENNY_ID then
        return false
    end

    local slots = pData.slots or {}
    local claimed = 0
    for _, slot in ipairs(slots) do
        if not slot.itemId then
            slot.itemId = itemId
            slot.doubled = false
            claimed = claimed + 1
        end
    end

    if claimed <= 0 then
        return false
    end

    local granted = 0
    for _, slot in ipairs(slots) do
        if slot.itemId == itemId and not slot.doubled then
            grantItem(player, itemId, 1, pData)
            slot.doubled = true
            granted = granted + 1
        end
    end

    pData.tookDamageThisFloor = false
    ConchBlessing.printDebug(string.format(
        "[Two Faced Penny] Claimed next collectible %d for %d slot(s), granted=%d.",
        itemId,
        claimed,
        granted
    ))
    return granted > 0
end

local function processObservedCollectible(player, pData, itemId, count)
    if not isValidCollectibleId(itemId) or itemId == TWO_FACED_PENNY_ID then
        return false
    end

    local remaining = tonumber(count) or 1
    remaining = remaining - consumeSuppressedAdd(pData, itemId, remaining)
    if remaining <= 0 then
        return false
    end

    if syncPennySlots(player, pData) <= 0 then
        return false
    end
    return claimNextCollectible(player, pData, itemId)
end

function M.onPostAddCollectible(_, itemId, _charge, _firstTime, _slot, _varData, player)
    if not player or not isValidCollectibleId(itemId) then
        return
    end
    if not isValidCollectibleId(TWO_FACED_PENNY_ID) then
        return
    end

    local pData = getPlayerData(player)
    if itemId == TWO_FACED_PENNY_ID then
        if pData.lastPennyCount == nil then
            pData.lastPennyCount = math.max(0, getPennyCount(player) - 1)
        end
        syncPennySlots(player, pData)
        recordCollectibleCount(player, pData, itemId)
        return
    end

    processObservedCollectible(player, pData, itemId, 1)
    recordCollectibleCount(player, pData, itemId)
end

function M.onPlayerUpdate(_, player)
    if not player or not isValidCollectibleId(TWO_FACED_PENNY_ID) then
        return
    end

    local pData = getPlayerData(player)
    local pennyCount = syncPennySlots(player, pData)

    if not HAS_POST_ADD_COLLECTIBLE and pennyCount > 0 then
        for _, change in ipairs(detectNewCollectibles(player, pData)) do
            processObservedCollectible(player, pData, change.itemId, change.delta)
        end
    end

    if pData.currentFloorKey == nil then
        pData.currentFloorKey = getFloorKey()
    end
end

function M.onDamage(_, entity, amount, flags, source, countdown)
    local player = entity:ToPlayer()
    if not player or not player:HasCollectible(TWO_FACED_PENNY_ID) then
        return
    end
    if DamageUtils.isSelfInflictedDamage(flags, source) then
        return
    end
    getPlayerData(player).tookDamageThisFloor = true
end

function M.onNewFloor(_)
    local floorKey = getFloorKey()
    for i = 0, game:GetNumPlayers() - 1 do
        local player = Isaac.GetPlayer(i)
        if player and player:HasCollectible(TWO_FACED_PENNY_ID) then
            local pData = getPlayerData(player)
            if pData.currentFloorKey and pData.currentFloorKey ~= floorKey then
                if not pData.tookDamageThisFloor then
                    local granted = false
                    for _, slot in ipairs(pData.slots or {}) do
                        if isValidCollectibleId(slot.itemId) then
                            grantItem(player, slot.itemId, 1, pData)
                            granted = true
                        end
                    end
                    if granted then
                        SFXManager():Play(SoundEffect.SOUND_POWERUP1, 1.0)
                        refreshCounts(player, pData)
                    end
                end
            end
            pData.tookDamageThisFloor = false
            pData.currentFloorKey = floorKey
            pData.lastPennyCount = getPennyCount(player)
        end
    end
end

function M.onGameStarted(_, isContinued)
    for i = 0, game:GetNumPlayers() - 1 do
        local player = Isaac.GetPlayer(i)
        if player then
            if not isContinued then
                player:GetData().__twofacedpenny = nil
            end
            local pData = getPlayerData(player)
            pData.currentFloorKey = getFloorKey()
            pData.slots = pData.slots or {}
            pData.lastPennyCount = math.min(#pData.slots, getPennyCount(player))
            syncPennySlots(player, pData)
            if not HAS_POST_ADD_COLLECTIBLE then
                refreshCounts(player, pData)
            end
        end
    end
end

return M
