local game = Game()
local DamageUtils = ConchBlessing.DamageUtils or require("scripts.lib.damage_utils")

ConchBlessing.magicmold = {}

local MAGIC_MOLD_ID = Isaac.GetItemIdByName("Magic Mold")

local function getFloorKey()
    local level = game:GetLevel()
    local stage = level:GetStage()
    local stageType = level:GetStageType()
    return tostring(stage) .. ":" .. tostring(stageType)
end

local function getPlayerData(player)
    local data = player:GetData()
    if not data.__magicmold then
        data.__magicmold = {
            pendingCount = 0,
            appliedCount = 0,
            targetItemId = nil,
            tookDamageThisFloor = false,
            currentFloorKey = nil,
            lastMoldCount = 0,
            lastCollectibleCounts = nil,
        }
    end
    return data.__magicmold
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
                if cur > prev and id ~= MAGIC_MOLD_ID and foundId == nil then
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

local function refreshCounts(player, pData)
    pData.lastCollectibleCounts = buildCollectibleCounts(player)
end

ConchBlessing.magicmold.onPlayerUpdate = function(_, player)
    if not player then return end
    if not MAGIC_MOLD_ID or MAGIC_MOLD_ID <= 0 then return end

    local moldCount = player:GetCollectibleNum(MAGIC_MOLD_ID, true)
    local pData = getPlayerData(player)

    if pData.lastMoldCount == nil then
        pData.lastMoldCount = moldCount
    end

    if moldCount > (pData.lastMoldCount or 0) then
        local diff = moldCount - (pData.lastMoldCount or 0)
        pData.pendingCount = (pData.pendingCount or 0) + diff
    end

    if moldCount > 0 and (pData.pendingCount or 0) > 0 then
        local foundId = detectNewCollectible(player, pData)
        if foundId and foundId > 0 then
            local toGrant = pData.pendingCount or 0
            if toGrant > 0 then
                for _ = 1, toGrant do
                    player:AddCollectible(foundId, 0, true)
                end
                pData.targetItemId = foundId
                pData.appliedCount = (pData.appliedCount or 0) + toGrant
                pData.pendingCount = 0
                pData.tookDamageThisFloor = false
                refreshCounts(player, pData)
            end
        end
    end

    pData.lastMoldCount = moldCount
    if pData.currentFloorKey == nil then
        pData.currentFloorKey = getFloorKey()
    end
end

ConchBlessing.magicmold.onDamage = function(_, entity, amount, flags, source, countdown)
    local player = entity:ToPlayer()
    if not player or not player:HasCollectible(MAGIC_MOLD_ID) then return end
    if DamageUtils.isSelfInflictedDamage(flags, source) then
        return
    end
    getPlayerData(player).tookDamageThisFloor = true
end

ConchBlessing.magicmold.onNewFloor = function(_)
    local floorKey = getFloorKey()
    for i = 0, game:GetNumPlayers() - 1 do
        local player = Isaac.GetPlayer(i)
        if player and player:HasCollectible(MAGIC_MOLD_ID) then
            local pData = getPlayerData(player)
            if pData.currentFloorKey and pData.currentFloorKey ~= floorKey then
                if not pData.tookDamageThisFloor then
                    local target = pData.targetItemId
                    local count = pData.appliedCount or 0
                    if target and target > 0 and count > 0 then
                        for _ = 1, count do
                            player:AddCollectible(target, 0, true)
                        end
                        SFXManager():Play(SoundEffect.SOUND_POWERUP1, 1.0)
                        refreshCounts(player, pData)
                    end
                end
            end
            pData.tookDamageThisFloor = false
            pData.currentFloorKey = floorKey
        end
    end
end

ConchBlessing.magicmold.onGameStarted = function(_, isContinued)
    if not isContinued then
        for i = 0, game:GetNumPlayers() - 1 do
            local player = Isaac.GetPlayer(i)
            if player then
                player:GetData().__magicmold = nil
            end
        end
    else
        for i = 0, game:GetNumPlayers() - 1 do
            local player = Isaac.GetPlayer(i)
            if player then
                local pData = getPlayerData(player)
                refreshCounts(player, pData)
                if pData.currentFloorKey == nil then
                    pData.currentFloorKey = getFloorKey()
                end
            end
        end
    end
end

return ConchBlessing.magicmold
