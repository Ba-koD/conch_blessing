local game = Game()
local DamageUtils = ConchBlessing.DamageUtils or require("scripts.lib.damage_utils")

ConchBlessing.twofacedpenny = {}

local TWO_FACED_PENNY_ID = Isaac.GetItemIdByName("Two Faced Penny")

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
            lastPennyCount = 0,
            lastCollectibleCounts = nil,
            slots = {},
            obtainedItems = {}, -- 이미 두 배 지급된 아이템 ID 저장 (Set)
        }
    end
    return data.__twofacedpenny
end

local function ensureSuppressMap(pData)
    if not pData.suppress then
        pData.suppress = {}
    end
    return pData.suppress
end

local function grantItem(player, itemId, count, pData)
    if count <= 0 then return end
    local suppress = ensureSuppressMap(pData)
    suppress[itemId] = (suppress[itemId] or 0) + count
    for _ = 1, count do
        player:AddCollectible(itemId, 0, true)
    end
end

local function buildCollectibleCounts(player)
    local counts = {}
    local maxId = CollectibleType.NUM_COLLECTIBLES or 0
    if maxId <= 0 then
        return counts
    end
    for id = 1, maxId - 1 do
        local ok, num = pcall(function() return player:GetCollectibleNum(id, true) end)
        if ok and type(num) == "number" then
            counts[id] = num
        end
    end
    return counts
end

local function detectNewCollectible(player, pData)
    local counts = pData.lastCollectibleCounts or buildCollectibleCounts(player)
    local maxId = CollectibleType.NUM_COLLECTIBLES or 0
    local foundId = nil
    local foundDelta = 0
    if maxId > 0 then
        for id = 1, maxId - 1 do
            local ok, cur = pcall(function() return player:GetCollectibleNum(id, true) end)
            if ok and type(cur) == "number" then
                local prev = counts[id] or 0
                if cur > prev and id ~= TWO_FACED_PENNY_ID and foundId == nil then
                    foundId = id
                    foundDelta = cur - prev
                end
                counts[id] = cur
            end
        end
    end
    pData.lastCollectibleCounts = counts
    return foundId, foundDelta
end

ConchBlessing.twofacedpenny.onPlayerUpdate = function(_, player)
    if not player then return end
    if not TWO_FACED_PENNY_ID or TWO_FACED_PENNY_ID <= 0 then return end

    local moldCount = player:GetCollectibleNum(TWO_FACED_PENNY_ID, true)
    local pData = getPlayerData(player)
    pData.slots = pData.slots or {}

    if pData.lastPennyCount == nil then
        pData.lastPennyCount = moldCount
    end

    if moldCount > (pData.lastPennyCount or 0) then
        local diff = moldCount - (pData.lastPennyCount or 0)
        for _ = 1, diff do
            table.insert(pData.slots, { itemId = nil })
        end
    elseif moldCount < (pData.lastPennyCount or 0) then
        while #pData.slots > moldCount do
            table.remove(pData.slots)
        end
    end

    if moldCount > 0 then
        local foundId, foundDelta = detectNewCollectible(player, pData)
        if foundId and foundId > 0 and foundDelta > 0 then
            local suppress = pData.suppress
            if suppress and suppress[foundId] and suppress[foundId] > 0 then
                local skipped = math.min(suppress[foundId], foundDelta)
                suppress[foundId] = suppress[foundId] - skipped
                foundDelta = foundDelta - skipped
            end
            for _ = 1, foundDelta do
                local slots = pData.slots or {}
                local pendingIndex = nil
                for i, slot in ipairs(slots) do
                    if not slot.itemId then
                        pendingIndex = i
                        break
                    end
                end

                if pendingIndex then
                    slots[pendingIndex].itemId = foundId
                    pData.tookDamageThisFloor = false
                    
                    -- 최초 획득인지 확인 (이미 두 배 지급된 아이템이 아니면)
                    pData.obtainedItems = pData.obtainedItems or {}
                    if not pData.obtainedItems[foundId] then
                        -- 최초 획득: 두 배 지급
                        grantItem(player, foundId, 1, pData)
                        pData.obtainedItems[foundId] = true
                    end
                    -- 이미 획득한 아이템이면 두 배 지급 안 함 (노피격 보너스만 슬롯에 저장)
                end
            end
        end
    end
    pData.lastPennyCount = moldCount
    if pData.currentFloorKey == nil then
        pData.currentFloorKey = getFloorKey()
    end
end

ConchBlessing.twofacedpenny.onDamage = function(_, entity, amount, flags, source, countdown)
    local player = entity:ToPlayer()
    if not player or not player:HasCollectible(TWO_FACED_PENNY_ID) then return end
    if DamageUtils.isSelfInflictedDamage(flags, source) then
        return
    end
    getPlayerData(player).tookDamageThisFloor = true
end

ConchBlessing.twofacedpenny.onNewFloor = function(_)
    local floorKey = getFloorKey()
    for i = 0, game:GetNumPlayers() - 1 do
        local player = Isaac.GetPlayer(i)
        if player and player:HasCollectible(TWO_FACED_PENNY_ID) then
            local pData = getPlayerData(player)
            if pData.currentFloorKey and pData.currentFloorKey ~= floorKey then
                if not pData.tookDamageThisFloor then
                    local slots = pData.slots or {}
                    local granted = false
                    for _, slot in ipairs(slots) do
                        if slot.itemId and slot.itemId > 0 then
                            grantItem(player, slot.itemId, 1, pData)
                            granted = true
                        end
                    end
                    if granted then
                        SFXManager():Play(SoundEffect.SOUND_POWERUP1, 1.0)
                    end
                end
            end
            pData.tookDamageThisFloor = false
            pData.currentFloorKey = floorKey
        end
    end
end

ConchBlessing.twofacedpenny.onGameStarted = function(_, isContinued)
    if not isContinued then
        for i = 0, game:GetNumPlayers() - 1 do
            local player = Isaac.GetPlayer(i)
            if player then
                player:GetData().__twofacedpenny = nil
            end
        end
    else
        for i = 0, game:GetNumPlayers() - 1 do
            local player = Isaac.GetPlayer(i)
            if player then
                local pData = getPlayerData(player)
                if pData.currentFloorKey == nil then
                    pData.currentFloorKey = getFloorKey()
                end
            end
        end
    end
end

return ConchBlessing.twofacedpenny
