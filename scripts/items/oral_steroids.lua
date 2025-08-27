ConchBlessing.oralsteroids = {}

local ORAL_STEROIDS_ID = Isaac.GetItemIdByName("Oral Steroids")

-- SaveManager integration
local SaveManager = require("scripts.lib.save_manager")

ConchBlessing.oralsteroids.data = {
    minMultiplier = 0.8,
    maxMultiplier = 1.5,
    speedDecrease = 0
}

ConchBlessing.oralsteroids.onEvaluateCache = function(_, player, cacheFlag)
    if not player:HasCollectible(ORAL_STEROIDS_ID) then return end
    
    local playerID = player:GetPlayerType()
    local itemNum = player:GetCollectibleNum(ORAL_STEROIDS_ID)
    
    if itemNum <= 0 then return end
    
    -- Prevent duplicate processing in the same frame
    if ConchBlessing.oralsteroids._lastProcessedFrame == Game():GetFrameCount() and 
       ConchBlessing.oralsteroids._lastProcessedPlayer == playerID and
       ConchBlessing.oralsteroids._lastProcessedItemNum == itemNum then
        return
    end
    
    -- Only process if this is actually a stat change for Oral Steroids
    -- Don't process if this is just a cache refresh from other items
    if not ConchBlessing.oralsteroids._lastItemCount then
        ConchBlessing.oralsteroids._lastItemCount = {}
    end
    if not ConchBlessing.oralsteroids._lastItemCount[playerID] then
        ConchBlessing.oralsteroids._lastItemCount[playerID] = 0
    end
    
    -- Only process if item count actually changed
    if ConchBlessing.oralsteroids._lastItemCount[playerID] == itemNum then
        ConchBlessing.printDebug("Oral Steroids: Item count unchanged (" .. itemNum .. "), skipping cache refresh")
        return
    end
    
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
            
            local combinedSeed = i + gameSeedHash
            
            ConchBlessing.printDebug("Oral Steroids RNG Debug #" .. i .. ":")
            ConchBlessing.printDebug("  Game Seed: " .. gameSeed)
            ConchBlessing.printDebug("  Game Seed Hash: " .. gameSeedHash)
            ConchBlessing.printDebug("  Item Count: " .. i)
            ConchBlessing.printDebug("  Combined Seed: " .. combinedSeed)
            
            rng:SetSeed(combinedSeed, 35)
            
            local newMultipliers = {
                tears = math.floor((rng:RandomFloat() * (ConchBlessing.oralsteroids.data.maxMultiplier - ConchBlessing.oralsteroids.data.minMultiplier) + ConchBlessing.oralsteroids.data.minMultiplier) * 100) / 100,
                damage = math.floor((rng:RandomFloat() * (ConchBlessing.oralsteroids.data.maxMultiplier - ConchBlessing.oralsteroids.data.minMultiplier) + ConchBlessing.oralsteroids.data.minMultiplier) * 100) / 100,
                range = math.floor((rng:RandomFloat() * (ConchBlessing.oralsteroids.data.maxMultiplier - ConchBlessing.oralsteroids.data.minMultiplier) + ConchBlessing.oralsteroids.data.minMultiplier) * 100) / 100,
                luck = math.floor((rng:RandomFloat() * (ConchBlessing.oralsteroids.data.maxMultiplier - ConchBlessing.oralsteroids.data.minMultiplier) + ConchBlessing.oralsteroids.data.minMultiplier) * 100) / 100
            }
            
            table.insert(ConchBlessing.oralsteroids.storedMultipliers[playerID], newMultipliers)
            
            ConchBlessing.printDebug(string.format("Oral Steroids #%d: Tears=%.2fx Damage=%.2fx Range=%.2fx Luck=%.2fx", 
                i, newMultipliers.tears, newMultipliers.damage, newMultipliers.range, newMultipliers.luck))
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
    
    local totalTears = 1.0
    local totalDamage = 1.0
    local totalRange = 1.0
    local totalLuck = 1.0
    
    local storedMultipliers = ConchBlessing.oralsteroids.storedMultipliers[playerID]
    for i = 1, math.min(itemNum, #storedMultipliers) do
        local multipliers = storedMultipliers[i]
        totalTears = totalTears * multipliers.tears
        totalDamage = totalDamage * multipliers.damage
        totalRange = totalRange * multipliers.range
        totalLuck = totalLuck * multipliers.luck
    end
    
    totalTears = math.max(ConchBlessing.oralsteroids.data.minMultiplier, totalTears)
    totalDamage = math.max(ConchBlessing.oralsteroids.data.minMultiplier, totalDamage)
    totalRange = math.max(ConchBlessing.oralsteroids.data.minMultiplier, totalRange)
    totalLuck = math.max(ConchBlessing.oralsteroids.data.minMultiplier, totalLuck)
    
    if cacheFlag == CacheFlag.CACHE_DAMAGE and itemNum ~= ConchBlessing.oralsteroids._lastFinalDebugItemNum then
        ConchBlessing.printDebug(string.format("Oral Steroids Final (x%d): Tears=%.2fx Damage=%.2fx Range=%.2fx Luck=%.2fx", 
            itemNum, totalTears, totalDamage, totalRange, totalLuck))
        ConchBlessing.oralsteroids._lastFinalDebugItemNum = itemNum
    end
    
    -- No direct stat application here; unified system will handle totals
    
    -- Update unified multipliers ONCE per item-count change (independent of cacheFlag order)
    do
        local lastIndividualMultipliers = storedMultipliers[#storedMultipliers]
        local uniqueKey = ORAL_STEROIDS_ID .. "_" .. #storedMultipliers
        ConchBlessing.stats.unifiedMultipliers:SetItemMultiplier(player, uniqueKey, "Tears", lastIndividualMultipliers.tears, "Oral Steroids #" .. #storedMultipliers)
        ConchBlessing.stats.unifiedMultipliers:SetItemMultiplier(player, uniqueKey, "Damage", lastIndividualMultipliers.damage, "Oral Steroids #" .. #storedMultipliers)
        ConchBlessing.stats.unifiedMultipliers:SetItemMultiplier(player, uniqueKey, "Range", lastIndividualMultipliers.range, "Oral Steroids #" .. #storedMultipliers)
        ConchBlessing.stats.unifiedMultipliers:SetItemMultiplier(player, uniqueKey, "Luck", lastIndividualMultipliers.luck, "Oral Steroids #" .. #storedMultipliers)
    end
    
    if cacheFlag == CacheFlag.CACHE_SPEED then
        local speedDecrease = ConchBlessing.oralsteroids.data.speedDecrease * itemNum
        ConchBlessing.stats.speed.applyAddition(player, -speedDecrease, ConchBlessing.oralsteroids.data.minMultiplier)
    end
    
    -- No-op for RANGE; unified system will render/apply on its own
    
    -- No-op for LUCK; unified system will render/apply on its own
    
    -- Mark this frame as processed to prevent duplicate calls
    ConchBlessing.oralsteroids._lastProcessedFrame = Game():GetFrameCount()
    ConchBlessing.oralsteroids._lastProcessedPlayer = playerID
    ConchBlessing.oralsteroids._lastProcessedItemNum = itemNum
    
    -- Record the item count that was processed
    ConchBlessing.oralsteroids._lastItemCount[playerID] = itemNum
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
                
                -- Load unified multipliers from SaveManager
                ConchBlessing.stats.unifiedMultipliers:LoadFromSaveManager(player)
                
                -- Apply stats and update unified system with unique keys
                for i = 1, #ConchBlessing.oralsteroids.storedMultipliers[playerID] do
                    local multipliers = ConchBlessing.oralsteroids.storedMultipliers[playerID][i]
                    local uniqueKey = ORAL_STEROIDS_ID .. "_" .. i
                    
                    ConchBlessing.stats.unifiedMultipliers:SetItemMultiplier(
                        player, uniqueKey, "Tears", multipliers.tears, "Oral Steroids #" .. i
                    )
                    ConchBlessing.stats.unifiedMultipliers:SetItemMultiplier(
                        player, uniqueKey, "Damage", multipliers.damage, "Oral Steroids #" .. i
                    )
                    ConchBlessing.stats.unifiedMultipliers:SetItemMultiplier(
                        player, uniqueKey, "Range", multipliers.range, "Oral Steroids #" .. i
                    )
                    ConchBlessing.stats.unifiedMultipliers:SetItemMultiplier(
                        player, uniqueKey, "Luck", multipliers.luck, "Oral Steroids #" .. i
                    )
                end
                
                -- Save unified multipliers to SaveManager
                ConchBlessing.stats.unifiedMultipliers:SaveToSaveManager(player)
                
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