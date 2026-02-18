local game = Game()
local DamageUtils = ConchBlessing.DamageUtils or require("scripts.lib.damage_utils")

ConchBlessing.polycoria = {}

local ITEM_ID = Isaac.GetItemIdByName("Polycoria")
local TWENTY_TWENTY = CollectibleType.COLLECTIBLE_20_20

local function getFloorKey()
    local level = game:GetLevel()
    local stage = level:GetStage()
    local stageType = level:GetStageType()
    return tostring(stage) .. ":" .. tostring(stageType)
end

-- Player data
local function getPlayerData(player)
    local data = player:GetData()
    if not data.__polycoria then
        data.__polycoria = {
            given2020Count = 0,
            tookDamageThisFloor = false,
            currentFloorKey = nil,
        }
    end
    return data.__polycoria
end

-- On pickup callback
ConchBlessing.polycoria.onPickup = function(player)
    ConchBlessing.printDebug("Polycoria: Item picked up")
    
    local pData = getPlayerData(player)
    pData.tookDamageThisFloor = false
    pData.currentFloorKey = getFloorKey()
    pData.lastPolycoriaCount = player:GetCollectibleNum(ITEM_ID, true)
    
    player:AddCollectible(TWENTY_TWENTY, 0, false)
    pData.given2020Count = (pData.given2020Count or 0) + 1
    
    ConchBlessing.printDebug("Polycoria: Gave 20/20 on pickup, count = " .. tostring(pData.given2020Count))
end

-- On damage
ConchBlessing.polycoria.onDamage = function(_, entity, amount, flags, src, countdown)
    local player = entity:ToPlayer()
    if not player or not player:HasCollectible(ITEM_ID) then return end
    
    -- Exclude self-inflicted damage (same logic as Minus Chain and Time = Power)
    if DamageUtils.isSelfInflictedDamage(flags, src) then
        ConchBlessing.printDebug(string.format("Polycoria: Ignored self-inflicted damage (flags=%d)", flags or -1))
        return
    end
    
    getPlayerData(player).tookDamageThisFloor = true
    ConchBlessing.printDebug("Polycoria: Player took damage this floor")
end

-- On new floor
ConchBlessing.polycoria.onNewFloor = function(_)
    local floorKey = getFloorKey()
    
    for i = 0, game:GetNumPlayers() - 1 do
        local player = Isaac.GetPlayer(i)
        if player and player:HasCollectible(ITEM_ID) then
            local pData = getPlayerData(player)
            
            if pData.currentFloorKey and pData.currentFloorKey ~= floorKey then
                if not pData.tookDamageThisFloor then
                    player:AddCollectible(TWENTY_TWENTY, 0, false)
                    pData.given2020Count = (pData.given2020Count or 0) + 1
                    SFXManager():Play(SoundEffect.SOUND_POWERUP1, 1.0)
                    
                    ConchBlessing.printDebug(string.format(
                        "Polycoria: No-hit bonus! Total 20/20: %d",
                        pData.given2020Count
                    ))
                else
                    ConchBlessing.printDebug("Polycoria: Took damage, no bonus")
                end
            end
            
            pData.tookDamageThisFloor = false
            pData.currentFloorKey = floorKey
        end
    end
end

-- On game start
ConchBlessing.polycoria.onGameStarted = function(_, isContinued)
    if not isContinued then
        for i = 0, game:GetNumPlayers() - 1 do
            local player = Isaac.GetPlayer(i)
            if player then
                player:GetData().__polycoria = nil
            end
        end
        ConchBlessing.printDebug("Polycoria: Data reset for new run")
    end
    
    for i = 0, game:GetNumPlayers() - 1 do
        local player = Isaac.GetPlayer(i)
        if player and player:HasCollectible(ITEM_ID) then
            local pData = getPlayerData(player)
            pData.currentFloorKey = getFloorKey()
            if not isContinued and (pData.given2020Count or 0) <= 0 then
                player:AddCollectible(TWENTY_TWENTY, 0, false)
                pData.given2020Count = 1
            end
            pData.lastPolycoriaCount = player:GetCollectibleNum(ITEM_ID, true)
        end
    end
end

-- Empty callbacks (등록된 콜백용)
ConchBlessing.polycoria.onPlayerUpdate = function(_, player)
    if not player or not player:HasCollectible(ITEM_ID) then return end
    
    local pData = getPlayerData(player)
    local polyCount = player:GetCollectibleNum(ITEM_ID, true)
    
    if pData.lastPolycoriaCount == nil then
        if (pData.given2020Count or 0) <= 0 and polyCount > 0 then
            for _ = 1, polyCount do
                player:AddCollectible(TWENTY_TWENTY, 0, true)
            end
            pData.given2020Count = polyCount
        end
        pData.lastPolycoriaCount = polyCount
        if not pData.currentFloorKey then
            pData.currentFloorKey = getFloorKey()
        end
        return
    end
    
    if polyCount > (pData.lastPolycoriaCount or 0) then
        local diff = polyCount - (pData.lastPolycoriaCount or 0)
        for _ = 1, diff do
            player:AddCollectible(TWENTY_TWENTY, 0, true)
        end
        pData.given2020Count = (pData.given2020Count or 0) + diff
        pData.tookDamageThisFloor = false
    end
    
    pData.lastPolycoriaCount = polyCount
end
return ConchBlessing.polycoria
