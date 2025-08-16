ConchBlessing.injectablsteroids = {}

local INJECTABLE_STEROIDS_ID = Isaac.GetItemIdByName("Injectable Steroids")

-- data table for upgrade system
ConchBlessing.injectablsteroids.data = {
    minMultiplier = 0.5,
    maxMultiplier = 2.0
}
ConchBlessing.injectablsteroids.storedMultipliers = {}

ConchBlessing.injectablsteroids.onUseItem = function(player, collectibleID, useFlags, activeSlot, customVarData)
    if collectibleID ~= INJECTABLE_STEROIDS_ID then
        return
    end
    
    if not player or not player.Position or not player.GetPlayerType then
        player = Isaac.GetPlayer(0)
        if not player then
            return
        end
    end
    
    player:AnimateCollectible(INJECTABLE_STEROIDS_ID, "Pickup", "PlayerPickupSparkle")
    
    local playerID = player:GetPlayerType()
    if not ConchBlessing.injectablsteroids.storedMultipliers then
        ConchBlessing.injectablsteroids.storedMultipliers = {}
    end
    if not ConchBlessing.injectablsteroids.storedMultipliers[playerID] then
        ConchBlessing.injectablsteroids.storedMultipliers[playerID] = {}
    end
    
    local newIndex = #ConchBlessing.injectablsteroids.storedMultipliers[playerID] + 1
    
    local newMultipliers = {
        speed = math.random() * (ConchBlessing.injectablsteroids.data.maxMultiplier - ConchBlessing.injectablsteroids.data.minMultiplier) + ConchBlessing.injectablsteroids.data.minMultiplier,
        tears = math.random() * (ConchBlessing.injectablsteroids.data.maxMultiplier - ConchBlessing.injectablsteroids.data.minMultiplier) + ConchBlessing.injectablsteroids.data.minMultiplier,
        damage = math.random() * (ConchBlessing.injectablsteroids.data.maxMultiplier - ConchBlessing.injectablsteroids.data.minMultiplier) + ConchBlessing.injectablsteroids.data.minMultiplier,
        range = math.random() * (ConchBlessing.injectablsteroids.data.maxMultiplier - ConchBlessing.injectablsteroids.data.minMultiplier) + ConchBlessing.injectablsteroids.data.minMultiplier,
        shotSpeed = math.random() * (ConchBlessing.injectablsteroids.data.maxMultiplier - ConchBlessing.injectablsteroids.data.minMultiplier) + ConchBlessing.injectablsteroids.data.minMultiplier,
        luck = math.random() * (ConchBlessing.injectablsteroids.data.maxMultiplier - ConchBlessing.injectablsteroids.data.minMultiplier) + ConchBlessing.injectablsteroids.data.minMultiplier
    }
    
    table.insert(ConchBlessing.injectablsteroids.storedMultipliers[playerID], newMultipliers)
    
    ConchBlessing.printDebug(string.format("Injectable Steroids #%d used: Speed=%.2fx Tears=%.2fx Damage=%.2fx Range=%.2fx ShotSpeed=%.2fx Luck=%.2fx", 
        newIndex, newMultipliers.speed, newMultipliers.tears, newMultipliers.damage, newMultipliers.range, newMultipliers.shotSpeed, newMultipliers.luck))
    
    SFXManager():Play(SoundEffect.SOUND_ISAAC_HURT_GRUNT, 1.0, 0, false, 1.0, 0)
    
    if not ConchBlessing.injectablsteroids._yellowIntensity then
        ConchBlessing.injectablsteroids._yellowIntensity = 0
    end
    
    ConchBlessing.injectablsteroids._yellowIntensity = ConchBlessing.injectablsteroids._yellowIntensity + 0.2
    
    player:AnimateCollectible(INJECTABLE_STEROIDS_ID, "Drop", "PlayerPickupSparkle")
    
    ConchBlessing.printDebug("Injectable Steroids use effect completed! Use count: " .. newIndex)
    
    return { Discharge = true, Remove = false, ShowAnim = true }
end


ConchBlessing.injectablsteroids.onEvaluateCache = function(_, player, cacheFlag)
    if not player:HasCollectible(INJECTABLE_STEROIDS_ID) then return end
    
    local playerID = player:GetPlayerType()
    local itemNum = player:GetCollectibleNum(INJECTABLE_STEROIDS_ID)
    
    if itemNum <= 0 then return end
    
    if not ConchBlessing.injectablsteroids.storedMultipliers then
        ConchBlessing.injectablsteroids.storedMultipliers = {}
    end
    
    if not ConchBlessing.injectablsteroids.storedMultipliers[playerID] then
        ConchBlessing.injectablsteroids.storedMultipliers[playerID] = {}
    end
    
    local useCount = #ConchBlessing.injectablsteroids.storedMultipliers[playerID]
    
    if useCount <= 0 then return end
    
    if cacheFlag == CacheFlag.CACHE_DAMAGE and useCount ~= (ConchBlessing.injectablsteroids._lastDebugUseCount or 0) then
        ConchBlessing.printDebug("Injectable Steroids: storedMultipliers count (use count): " .. useCount)
        ConchBlessing.injectablsteroids._lastDebugUseCount = useCount
    end
    
    local totalSpeed = 1.0
    local totalTears = 1.0
    local totalDamage = 1.0
    local totalRange = 1.0
    local totalShotSpeed = 1.0
    local totalLuck = 1.0
    
    local storedMultipliers = ConchBlessing.injectablsteroids.storedMultipliers[playerID]
    for i = 1, useCount do
        local multipliers = storedMultipliers[i]
        totalSpeed = totalSpeed * multipliers.speed
        totalTears = totalTears * multipliers.tears
        totalDamage = totalDamage * multipliers.damage
        totalRange = totalRange * multipliers.range
        totalShotSpeed = totalShotSpeed * multipliers.shotSpeed
        totalLuck = totalLuck * multipliers.luck
    end
    
    totalSpeed = math.max(ConchBlessing.injectablsteroids.data.minMultiplier, totalSpeed)
    totalTears = math.max(ConchBlessing.injectablsteroids.data.minMultiplier, totalTears)
    totalDamage = math.max(ConchBlessing.injectablsteroids.data.minMultiplier, totalDamage)
    totalRange = math.max(ConchBlessing.injectablsteroids.data.minMultiplier, totalRange)
    totalShotSpeed = math.max(ConchBlessing.injectablsteroids.data.minMultiplier, totalShotSpeed)
    totalLuck = math.max(ConchBlessing.injectablsteroids.data.minMultiplier, totalLuck)
    
    if cacheFlag == CacheFlag.CACHE_DAMAGE and useCount ~= (ConchBlessing.injectablsteroids._lastFinalDebugUseCount or 0) then
        ConchBlessing.printDebug(string.format("Injectable Steroids Final (x%d uses): Speed=%.2fx Tears=%.2fx Damage=%.2fx Range=%.2fx ShotSpeed=%.2fx Luck=%.2fx", 
            useCount, totalSpeed, totalTears, totalDamage, totalRange, totalShotSpeed, totalLuck))
        ConchBlessing.injectablsteroids._lastFinalDebugUseCount = useCount
    end
    
    if cacheFlag == CacheFlag.CACHE_FIREDELAY then
        ConchBlessing.stats.tears.applyMultiplier(player, totalTears, ConchBlessing.injectablsteroids.data.minMultiplier)
    end
    
    if cacheFlag == CacheFlag.CACHE_DAMAGE then
        ConchBlessing.stats.damage.applyMultiplier(player, totalDamage, ConchBlessing.injectablsteroids.data.minMultiplier)
    end
    
    if cacheFlag == CacheFlag.CACHE_SPEED then
        player.MoveSpeed = player.MoveSpeed * totalSpeed
    end
    
    if cacheFlag == CacheFlag.CACHE_RANGE then
        player.TearRange = player.TearRange * totalRange
    end
    
    if cacheFlag == CacheFlag.CACHE_LUCK and player.Luck > 0 then
        player.Luck = player.Luck * totalLuck
    end
    
    if cacheFlag == CacheFlag.CACHE_SHOTSPEED then
        player.ShotSpeed = player.ShotSpeed * totalShotSpeed
    end
end

-- initialize data when game started
ConchBlessing.injectablsteroids.onGameStarted = function(_)
    ConchBlessing.injectablsteroids.storedMultipliers = {}
    ConchBlessing.injectablsteroids._yellowIntensity = 0
end

-- charge restore when new level
ConchBlessing.injectablsteroids.onNewLevel = function(_)
    local player = Isaac.GetPlayer(0)
    if not player then
        return
    end
    
    if not player:HasCollectible(INJECTABLE_STEROIDS_ID) then
        return
    end
    
    local activeItem = player:GetActiveItem(ActiveSlot.SLOT_PRIMARY)
    if activeItem == INJECTABLE_STEROIDS_ID then
        player:SetActiveCharge(1, ActiveSlot.SLOT_PRIMARY)
    end
end

-- upgrade related functions
ConchBlessing.injectablsteroids.onBeforeChange = function(upgradePos, pickup, itemData)
    return ConchBlessing.template.negative.onBeforeChange(upgradePos, pickup, ConchBlessing.injectablsteroids.data)
end

ConchBlessing.injectablsteroids.onAfterChange = function(upgradePos, pickup, itemData)
    return ConchBlessing.template.negative.onAfterChange(upgradePos, pickup, ConchBlessing.injectablsteroids.data)
end

ConchBlessing.injectablsteroids.onUpdate = function(_)
    ConchBlessing.template.onUpdate(ConchBlessing.injectablsteroids.data)
    
    if ConchBlessing.injectablsteroids._yellowIntensity and ConchBlessing.injectablsteroids._yellowIntensity > 0 then
        local player = Isaac.GetPlayer(0)
        if player then
            local yellowIntensity = math.min(ConchBlessing.injectablsteroids._yellowIntensity or 0, 1.0)
            
            local baseColor = Color(
                1 + (0.15 * yellowIntensity),
                1 + (0.1 * yellowIntensity),
                1 - (0.05 * yellowIntensity),
                1,
                0.15 * yellowIntensity,
                0.1 * yellowIntensity,
                -0.05 * yellowIntensity
            )
            
            player:SetColor(baseColor, 0, 0, false, false)
        end
    end
end