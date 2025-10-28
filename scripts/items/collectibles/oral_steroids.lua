ConchBlessing.oralsteroids = {}

local ORAL_STEROIDS_ID = Isaac.GetItemIdByName("Oral Steroids")

-- SaveManager integration
local SaveManager = require("scripts.lib.save_manager")

-- STATS: Item stat modifiers (Dark Rock style)
ConchBlessing.oralsteroids.STATS = {
    MIN_MULTIPLIER = 0.8,        -- Minimum random multiplier value
    MAX_MULTIPLIER = 1.5,        -- Maximum random multiplier value
}

ConchBlessing.oralsteroids.data = {
    speedDecrease = 0
}

ConchBlessing.oralsteroids.onEvaluateCache = function(_, player, cacheFlag)
    if not player:HasCollectible(ORAL_STEROIDS_ID) then return end
    
    local playerID = player:GetPlayerType()
    local itemNum = player:GetCollectibleNum(ORAL_STEROIDS_ID)
    
    if itemNum <= 0 then return end
    
    -- Prevent duplicate processing in the same frame for the same item count
    if ConchBlessing.oralsteroids._lastProcessedFrame == Game():GetFrameCount() and 
       ConchBlessing.oralsteroids._lastProcessedPlayer == playerID and
       ConchBlessing.oralsteroids._lastProcessedItemNum == itemNum then
        return
    end
    
    -- Track item count for comparison
    if not ConchBlessing.oralsteroids._lastItemCount then
        ConchBlessing.oralsteroids._lastItemCount = {}
    end
    if not ConchBlessing.oralsteroids._lastItemCount[playerID] then
        ConchBlessing.oralsteroids._lastItemCount[playerID] = 0
    end
    
    local itemCountChanged = ConchBlessing.oralsteroids._lastItemCount[playerID] ~= itemNum
    if not itemCountChanged then
        ConchBlessing.printDebug("Oral Steroids: Item count unchanged (" .. itemNum .. "), checking if multipliers need initialization")
    end
    
    if not ConchBlessing.oralsteroids.storedMultipliers then
        ConchBlessing.oralsteroids.storedMultipliers = {}
    end
    
    if not ConchBlessing.oralsteroids.storedMultipliers[playerID] then
        ConchBlessing.oralsteroids.storedMultipliers[playerID] = {}
    end
    
    local storedCount = #ConchBlessing.oralsteroids.storedMultipliers[playerID]
    
    -- If storedMultipliers is empty but we have saved data, load it first
    if storedCount == 0 and itemNum > 0 then
        local playerSave = SaveManager.GetRunSave(player)
        if playerSave and playerSave.oralSteroids and #playerSave.oralSteroids > 0 then
            ConchBlessing.oralsteroids.storedMultipliers[playerID] = playerSave.oralSteroids
            storedCount = #ConchBlessing.oralsteroids.storedMultipliers[playerID]
            ConchBlessing.printDebug(string.format("Oral Steroids: Loaded %d multipliers from SaveManager in onEvaluateCache", storedCount))
            
            -- Check if unified system already has the data loaded
            local unifiedData = ConchBlessing.stats.unifiedMultipliers[playerID]
            local alreadyLoaded = false
            if unifiedData and unifiedData.itemAdditiveMultipliers and unifiedData.itemAdditiveMultipliers[ORAL_STEROIDS_ID] then
                local unifiedDamage = unifiedData.itemAdditiveMultipliers[ORAL_STEROIDS_ID]["Damage"]
                if unifiedDamage and unifiedDamage.cumulative then
                    alreadyLoaded = true
                    ConchBlessing.printDebug("Oral Steroids: Unified system already has multipliers loaded, skipping registration")
                end
            end
            
            -- Register loaded multipliers to unified system ONLY if not already loaded
            if not alreadyLoaded then
                ConchBlessing.printDebug("Oral Steroids: Registering multipliers to unified system")
                for i = 1, storedCount do
                    local m = ConchBlessing.oralsteroids.storedMultipliers[playerID][i]
                    ConchBlessing.stats.unifiedMultipliers:SetItemAdditiveMultiplier(player, ORAL_STEROIDS_ID, "Tears", m.tears or 1.0, "Oral Steroids #" .. i)
                    ConchBlessing.stats.unifiedMultipliers:SetItemAdditiveMultiplier(player, ORAL_STEROIDS_ID, "Damage", m.damage or 1.0, "Oral Steroids #" .. i)
                    ConchBlessing.stats.unifiedMultipliers:SetItemAdditiveMultiplier(player, ORAL_STEROIDS_ID, "Range", m.range or 1.0, "Oral Steroids #" .. i)
                    ConchBlessing.stats.unifiedMultipliers:SetItemAdditiveMultiplier(player, ORAL_STEROIDS_ID, "Luck", m.luck or 1.0, "Oral Steroids #" .. i)
                    ConchBlessing.printDebug(string.format("  #%d registered: Tears=%.2f Damage=%.2f Range=%.2f Luck=%.2f", 
                        i, m.tears or 0, m.damage or 0, m.range or 0, m.luck or 0))
                end
                ConchBlessing.stats.unifiedMultipliers:SaveToSaveManager(player)
            end
            
            -- Update _lastItemCount to mark as already processed
            if not ConchBlessing.oralsteroids._lastItemCount then
                ConchBlessing.oralsteroids._lastItemCount = {}
            end
            ConchBlessing.oralsteroids._lastItemCount[playerID] = storedCount
            
            -- Recalculate itemCountChanged after loading
            itemCountChanged = ConchBlessing.oralsteroids._lastItemCount[playerID] ~= itemNum
            ConchBlessing.printDebug(string.format("Oral Steroids: After loading, _lastItemCount=%d, itemNum=%d, itemCountChanged=%s", 
                ConchBlessing.oralsteroids._lastItemCount[playerID], itemNum, tostring(itemCountChanged)))
        end
    end
    
    -- Generate new multipliers if needed (item count increased or storedMultipliers doesn't have enough)
    if itemNum > storedCount then
        for i = storedCount + 1, itemNum do
            -- Use math.random() per stat for independent randomness
            local function rollStat()
                local r = math.random()
                local span = ConchBlessing.oralsteroids.STATS.MAX_MULTIPLIER - ConchBlessing.oralsteroids.STATS.MIN_MULTIPLIER
                local value = math.floor((r * span + ConchBlessing.oralsteroids.STATS.MIN_MULTIPLIER) * 100) / 100
                ConchBlessing.printDebug("Oral Steroids rollStat r=" .. string.format("%.6f", r) .. ", value=" .. string.format("%.2f", value))
                return value
            end

            local newMultipliers = {
                tears = rollStat(),
                damage = rollStat(),
                range = rollStat(),
                luck = rollStat()
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
    elseif storedCount > 0 and storedCount < itemNum then
        ConchBlessing.printDebug(string.format("Oral Steroids: Warning - storedCount (%d) < itemNum (%d), this shouldn't happen", storedCount, itemNum))
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
    
    totalTears = math.max(ConchBlessing.oralsteroids.STATS.MIN_MULTIPLIER, totalTears)
    totalDamage = math.max(ConchBlessing.oralsteroids.STATS.MIN_MULTIPLIER, totalDamage)
    totalRange = math.max(ConchBlessing.oralsteroids.STATS.MIN_MULTIPLIER, totalRange)
    totalLuck = math.max(ConchBlessing.oralsteroids.STATS.MIN_MULTIPLIER, totalLuck)
    
    if cacheFlag == CacheFlag.CACHE_DAMAGE and itemNum ~= ConchBlessing.oralsteroids._lastFinalDebugItemNum then
        ConchBlessing.printDebug(string.format("Oral Steroids Final (x%d): Tears=%.2fx Damage=%.2fx Range=%.2fx Luck=%.2fx", 
            itemNum, totalTears, totalDamage, totalRange, totalLuck))
        ConchBlessing.oralsteroids._lastFinalDebugItemNum = itemNum
    end
    
    -- No direct stat application here; unified system will handle totals
    
    -- Update unified multipliers ONLY when item count changed (to prevent duplicate application on game load)
    if itemCountChanged and #storedMultipliers > 0 then
        local lastIndividualMultipliers = storedMultipliers[#storedMultipliers]
        -- Always treat as additive multiplier stacking
        ConchBlessing.stats.unifiedMultipliers:SetItemAdditiveMultiplier(player, ORAL_STEROIDS_ID, "Tears", lastIndividualMultipliers.tears, "Oral Steroids #" .. #storedMultipliers)
        ConchBlessing.stats.unifiedMultipliers:SetItemAdditiveMultiplier(player, ORAL_STEROIDS_ID, "Damage", lastIndividualMultipliers.damage, "Oral Steroids #" .. #storedMultipliers)
        ConchBlessing.stats.unifiedMultipliers:SetItemAdditiveMultiplier(player, ORAL_STEROIDS_ID, "Range", lastIndividualMultipliers.range, "Oral Steroids #" .. #storedMultipliers)
        ConchBlessing.stats.unifiedMultipliers:SetItemAdditiveMultiplier(player, ORAL_STEROIDS_ID, "Luck", lastIndividualMultipliers.luck, "Oral Steroids #" .. #storedMultipliers)
        ConchBlessing.printDebug(string.format("Oral Steroids: Applied unified multipliers for item #%d", #storedMultipliers))
    elseif not itemCountChanged then
        ConchBlessing.printDebug("Oral Steroids: Skipped unified multiplier application (item count unchanged, unified system already loaded)")
    elseif #storedMultipliers == 0 then
        ConchBlessing.printDebug("Oral Steroids: Warning - storedMultipliers is empty, cannot apply unified multipliers")
    end
    
    if cacheFlag == CacheFlag.CACHE_SPEED then
        local speedDecrease = ConchBlessing.oralsteroids.data.speedDecrease * itemNum
        ConchBlessing.stats.speed.applyAddition(player, -speedDecrease, ConchBlessing.oralsteroids.STATS.MIN_MULTIPLIER)
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
        local haveArrays = playerSave and playerSave.oralSteroids
        local haveUnified = playerSave and playerSave.unifiedMultipliers
        if not ConchBlessing.oralsteroids.storedMultipliers then
            ConchBlessing.oralsteroids.storedMultipliers = {}
        end
        local playerID = player:GetPlayerType()
        ConchBlessing.oralsteroids.storedMultipliers[playerID] = haveArrays or {}
        
        -- Initialize _lastItemCount
        if not ConchBlessing.oralsteroids._lastItemCount then
            ConchBlessing.oralsteroids._lastItemCount = {}
        end
        
        if haveUnified then
            -- Unified system's POST_GAME_STARTED already loaded multipliers
            -- Set _lastItemCount to stored array count to mark as "already processed"
            local storedCount = #(haveArrays or {})
            ConchBlessing.oralsteroids._lastItemCount[playerID] = storedCount
            ConchBlessing.printDebug(string.format("Oral Steroids: Set _lastItemCount[%d] = %d (stored count, unified system loaded)", playerID, storedCount))
            
            -- Debug: print what was loaded
            if haveArrays and #haveArrays > 0 then
                ConchBlessing.printDebug(string.format("Oral Steroids: Loaded %d stored multipliers:", #haveArrays))
                for i = 1, #haveArrays do
                    local m = haveArrays[i]
                    ConchBlessing.printDebug(string.format("  #%d: Tears=%.2f Damage=%.2f Range=%.2f Luck=%.2f", 
                        i, m.tears or 0, m.damage or 0, m.range or 0, m.luck or 0))
                end
            end
        elseif haveArrays and #haveArrays > 0 then
            -- Reconstruct unified from arrays (first-time migration), using additive-mult stacking semantics
            for i = 1, #haveArrays do
                local m = haveArrays[i]
                ConchBlessing.stats.unifiedMultipliers:SetItemAdditiveMultiplier(player, ORAL_STEROIDS_ID, "Tears", m.tears or 1.0, "Oral Steroids #" .. i)
                ConchBlessing.stats.unifiedMultipliers:SetItemAdditiveMultiplier(player, ORAL_STEROIDS_ID, "Damage", m.damage or 1.0, "Oral Steroids #" .. i)
                ConchBlessing.stats.unifiedMultipliers:SetItemAdditiveMultiplier(player, ORAL_STEROIDS_ID, "Range", m.range or 1.0, "Oral Steroids #" .. i)
                ConchBlessing.stats.unifiedMultipliers:SetItemAdditiveMultiplier(player, ORAL_STEROIDS_ID, "Luck", m.luck or 1.0, "Oral Steroids #" .. i)
            end
            ConchBlessing.stats.unifiedMultipliers:SaveToSaveManager(player)
            ConchBlessing.oralsteroids._lastItemCount[playerID] = #haveArrays
            ConchBlessing.printDebug(string.format("Oral Steroids: Unified multipliers reconstructed from arrays and saved, _lastItemCount[%d] = %d", playerID, #haveArrays))
        else
            ConchBlessing.oralsteroids._lastItemCount[playerID] = 0
            ConchBlessing.printDebug("Oral Steroids: No saved data, initializing empty state")
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

-- Register PRE_DATA_SAVE sanitizer for this item's run data only
do
    local sm = SaveManager
    local mod = ConchBlessing and ConchBlessing.originalMod
    if sm and mod and mod.__SAVEMANAGER_UNIQUE_KEY and sm.SaveCallbacks then
        local callbackKey = mod.__SAVEMANAGER_UNIQUE_KEY .. sm.SaveCallbacks.PRE_DATA_SAVE
        mod:AddCallback(callbackKey, function(saveData)
            if saveData and saveData.game and saveData.game.run then
                for _, playerRun in pairs(saveData.game.run) do
                    local arr = playerRun and playerRun.oralSteroids
                    if type(arr) == "table" then
                        -- Compact sparse array entries
                        local compacted = {}
                        local count = 0
                        for i = 1, #arr do
                            local v = arr[i]
                            if v ~= nil then
                                count = count + 1
                                compacted[count] = v
                            end
                        end
                        playerRun.oralSteroids = compacted
                    end
                end
            end
            if ConchBlessing and ConchBlessing.Config and ConchBlessing.Config.debugMode then
                ConchBlessing.printDebug("[OralSteroids] PRE_DATA_SAVE sanitized oralSteroids array")
            end
            return saveData
        end)
    end
end