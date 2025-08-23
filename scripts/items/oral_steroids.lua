ConchBlessing.oralsteroids = {}

local ORAL_STEROIDS_ID = Isaac.GetItemIdByName("Oral Steroids")

-- SaveManager integration
local SaveManager = require("scripts.lib.save_manager")

ConchBlessing.oralsteroids.data = {
    minMultiplier = 0.8,
    maxMultiplier = 1.5,
    speedDecrease = 0,
    shotSpeedMin = 0.9,
    shotSpeedMax = 1.1
}

ConchBlessing.oralsteroids.onEvaluateCache = function(_, player, cacheFlag)
    if not player:HasCollectible(ORAL_STEROIDS_ID) then return end
    
    local playerID = player:GetPlayerType()
    local itemNum = player:GetCollectibleNum(ORAL_STEROIDS_ID)
    
    if itemNum <= 0 then return end
    
    if not ConchBlessing.oralsteroids.storedMultipliers then
        ConchBlessing.oralsteroids.storedMultipliers = {}
    end
    
    if not ConchBlessing.oralsteroids.storedMultipliers[playerID] then
        ConchBlessing.oralsteroids.storedMultipliers[playerID] = {}
    end
    
    local storedCount = #ConchBlessing.oralsteroids.storedMultipliers[playerID]
    if itemNum > storedCount then
        for i = storedCount + 1, itemNum do
            local rng = RNG()
            local gameSeed = Game():GetSeeds():GetStartSeedString()
            local gameSeedHash = 0
            
            for j = 1, #gameSeed do
                local char = string.byte(gameSeed, j)
                gameSeedHash = gameSeedHash + char * (j * 31 + char)
            end
            
            local combinedSeed = i * 1000000 + gameSeedHash
            
            ConchBlessing.printDebug("Oral Steroids RNG Debug #" .. i .. ":")
            ConchBlessing.printDebug("  Game Seed: " .. gameSeed)
            ConchBlessing.printDebug("  Game Seed Hash: " .. gameSeedHash)
            ConchBlessing.printDebug("  Item Count: " .. i)
            ConchBlessing.printDebug("  Combined Seed: " .. combinedSeed)
            
            rng:SetSeed(combinedSeed, 35)
            
            local newMultipliers = {
                --speed = math.floor((rng:RandomFloat() * (ConchBlessing.oralsteroids.data.maxMultiplier - ConchBlessing.oralsteroids.data.minMultiplier) + ConchBlessing.oralsteroids.data.minMultiplier) * 100) / 100,
                tears = math.floor((rng:RandomFloat() * (ConchBlessing.oralsteroids.data.maxMultiplier - ConchBlessing.oralsteroids.data.minMultiplier) + ConchBlessing.oralsteroids.data.minMultiplier) * 100) / 100,
                damage = math.floor((rng:RandomFloat() * (ConchBlessing.oralsteroids.data.maxMultiplier - ConchBlessing.oralsteroids.data.minMultiplier) + ConchBlessing.oralsteroids.data.minMultiplier) * 100) / 100,
                range = math.floor((rng:RandomFloat() * (ConchBlessing.oralsteroids.data.maxMultiplier - ConchBlessing.oralsteroids.data.minMultiplier) + ConchBlessing.oralsteroids.data.minMultiplier) * 100) / 100,
                shotSpeed = math.floor((rng:RandomFloat() * (ConchBlessing.oralsteroids.data.shotSpeedMax - ConchBlessing.oralsteroids.data.shotSpeedMin) + ConchBlessing.oralsteroids.data.shotSpeedMin) * 100) / 100,
                luck = math.floor((rng:RandomFloat() * (ConchBlessing.oralsteroids.data.maxMultiplier - ConchBlessing.oralsteroids.data.minMultiplier) + ConchBlessing.oralsteroids.data.minMultiplier) * 100) / 100
            }
            
            table.insert(ConchBlessing.oralsteroids.storedMultipliers[playerID], newMultipliers)
            
            ConchBlessing.printDebug(string.format("Oral Steroids #%d: Tears=%.2fx Damage=%.2fx Range=%.2fx ShotSpeed=%.2fx Luck=%.2fx", 
                i, newMultipliers.tears, newMultipliers.damage, newMultipliers.range, newMultipliers.shotSpeed, newMultipliers.luck))
        end
        
        ConchBlessing.printDebug("Oral Steroids: Added " .. (itemNum - storedCount) .. " new multipliers")
        
        local playerSave = SaveManager.GetRunSave(player)
        if playerSave then
            if not playerSave.oralSteroids then
                playerSave.oralSteroids = {}
            end
            playerSave.oralSteroids = ConchBlessing.oralsteroids.storedMultipliers[playerID]
            SaveManager.Save()
            ConchBlessing.printDebug("Oral Steroids: Data saved to SaveManager!")
        end
    end
    
    if cacheFlag == CacheFlag.CACHE_DAMAGE and itemNum ~= ConchBlessing.oralsteroids._lastDebugItemNum then
        ConchBlessing.printDebug("Oral Steroids: storedMultipliers count: " .. #ConchBlessing.oralsteroids.storedMultipliers[playerID])
        ConchBlessing.oralsteroids._lastDebugItemNum = itemNum
    end
    
    local totalSpeed = 1.0
    local totalTears = 1.0
    local totalDamage = 1.0
    local totalRange = 1.0
    local totalShotSpeed = 1.0
    local totalLuck = 1.0
    
    local storedMultipliers = ConchBlessing.oralsteroids.storedMultipliers[playerID]
    for i = 1, math.min(itemNum, #storedMultipliers) do
        local multipliers = storedMultipliers[i]
        --totalSpeed = totalSpeed * multipliers.speed
        totalTears = totalTears * multipliers.tears
        totalDamage = totalDamage * multipliers.damage
        totalRange = totalRange * multipliers.range
        totalShotSpeed = totalShotSpeed * multipliers.shotSpeed
        totalLuck = totalLuck * multipliers.luck
    end
    
    --totalSpeed = math.max(ConchBlessing.oralsteroids.data.minMultiplier, totalSpeed)
    totalTears = math.max(ConchBlessing.oralsteroids.data.minMultiplier, totalTears)
    totalDamage = math.max(ConchBlessing.oralsteroids.data.minMultiplier, totalDamage)
    totalRange = math.max(ConchBlessing.oralsteroids.data.minMultiplier, totalRange)
    totalShotSpeed = math.max(ConchBlessing.oralsteroids.data.minMultiplier, totalShotSpeed)
    totalLuck = math.max(ConchBlessing.oralsteroids.data.minMultiplier, totalLuck)
    
    if cacheFlag == CacheFlag.CACHE_DAMAGE and itemNum ~= ConchBlessing.oralsteroids._lastFinalDebugItemNum then
        ConchBlessing.printDebug(string.format("Oral Steroids Final (x%d): Tears=%.2fx Damage=%.2fx Range=%.2fx ShotSpeed=%.2fx Luck=%.2fx", 
            itemNum, totalTears, totalDamage, totalRange, totalShotSpeed, totalLuck))
        ConchBlessing.oralsteroids._lastFinalDebugItemNum = itemNum
    end
    
    if cacheFlag == CacheFlag.CACHE_FIREDELAY then
        ConchBlessing.stats.tears.applyMultiplier(player, totalTears, ConchBlessing.oralsteroids.data.minMultiplier)
    end
    
    if cacheFlag == CacheFlag.CACHE_DAMAGE then
        ConchBlessing.stats.damage.applyMultiplier(player, totalDamage, ConchBlessing.oralsteroids.data.minMultiplier)
    end
    
    if cacheFlag == CacheFlag.CACHE_SPEED then
        local speedDecrease = ConchBlessing.oralsteroids.data.speedDecrease * itemNum
        player.MoveSpeed = player.MoveSpeed - speedDecrease
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
ConchBlessing.oralsteroids.onGameStarted = function(_)
    local player = Isaac.GetPlayer(0)
    if player then
        local playerSave = SaveManager.GetRunSave(player)
        if playerSave and playerSave.oralSteroids then
            local playerID = player:GetPlayerType()
            if not ConchBlessing.oralsteroids.storedMultipliers then
                ConchBlessing.oralsteroids.storedMultipliers = {}
            end
            ConchBlessing.oralsteroids.storedMultipliers[playerID] = playerSave.oralSteroids
            ConchBlessing.printDebug("Oral Steroids: Loaded " .. #playerSave.oralSteroids .. " multipliers from SaveManager")
            
            local itemNum = player:GetCollectibleNum(ORAL_STEROIDS_ID)
            if itemNum > 0 then
                ConchBlessing.printDebug("Oral Steroids: Applying stats on game start for " .. itemNum .. " items")
                ConchBlessing.oralsteroids.onEvaluateCache(_, player, CacheFlag.CACHE_DAMAGE)
                ConchBlessing.oralsteroids.onEvaluateCache(_, player, CacheFlag.CACHE_FIREDELAY)
                ConchBlessing.oralsteroids.onEvaluateCache(_, player, CacheFlag.CACHE_SPEED)
                ConchBlessing.oralsteroids.onEvaluateCache(_, player, CacheFlag.CACHE_RANGE)
                ConchBlessing.oralsteroids.onEvaluateCache(_, player, CacheFlag.CACHE_LUCK)
                ConchBlessing.oralsteroids.onEvaluateCache(_, player, CacheFlag.CACHE_SHOTSPEED)
                ConchBlessing.printDebug("Oral Steroids: Stats applied on game start!")
            end
        else
            ConchBlessing.oralsteroids.storedMultipliers = {}
            ConchBlessing.printDebug("Oral Steroids: No saved data, initializing empty table")
        end
    else
        ConchBlessing.oralsteroids.storedMultipliers = {}
        ConchBlessing.printDebug("Oral Steroids: No player found, initializing empty table")
    end
    
    ConchBlessing.printDebug("Oral Steroids: onGameStarted called!")
    ConchBlessing.printDebug("Oral Steroids data initialized!")
    ConchBlessing.printDebug("storedMultipliers table created!")
end

-- upgrade related functions
ConchBlessing.oralsteroids.onBeforeChange = function(upgradePos, pickup, itemData)
    return ConchBlessing.template.neutral.onBeforeChange(upgradePos, pickup, ConchBlessing.oralsteroids.data)
end

ConchBlessing.oralsteroids.onAfterChange = function(upgradePos, pickup, itemData)
    return ConchBlessing.template.neutral.onAfterChange(upgradePos, pickup, ConchBlessing.oralsteroids.data)
end

-- subtle effect when stats are applied
ConchBlessing.oralsteroids.onUpdate = function(_)
    ConchBlessing.template.onUpdate(ConchBlessing.oralsteroids.data)
end