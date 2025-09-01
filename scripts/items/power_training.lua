ConchBlessing.powertraining = {}

local POWER_TRAINING_ID = Isaac.GetItemIdByName("Power Training")

-- SaveManager integration
local SaveManager = require("scripts.lib.save_manager")

local json = nil
pcall(function() json = require("json") end)
if not json then
    json = {
        encode = function(data) 
            if type(data) == "table" then
                local result = "{"
                for k, v in pairs(data) do
                    if result ~= "{" then result = result .. ", " end
                    result = result .. tostring(k) .. "=" .. tostring(v)
                end
                result = result .. "}"
                return result
            else
                return tostring(data)
            end
        end,
        decode = function(str) return {} end,
    }
end

ConchBlessing.powertraining.data = {
    minMultiplier = 1.0,
    maxMultiplier = 1.3,
    speedDecrease = 0
}

ConchBlessing.powertraining.onUseItem = function(player, collectibleID, useFlags, activeSlot, customVarData)
    ConchBlessing.printDebug("=== Power Training onUseItem START ===")
    ConchBlessing.printDebug("collectibleID: " .. tostring(collectibleID))
    ConchBlessing.printDebug("POWER_TRAINING_ID: " .. tostring(POWER_TRAINING_ID))
    
    if collectibleID ~= POWER_TRAINING_ID then
        ConchBlessing.printDebug("collectibleID mismatch, returning")
        return
    end
    
    if not player or not player.Position or not player.GetPlayerType then
        ConchBlessing.printDebug("Invalid player, getting player 0")
        player = Isaac.GetPlayer(0)
        if not player then
            ConchBlessing.printDebug("Failed to get player 0")
            return
        end
    end
    
    ConchBlessing.printDebug("Player found, animating collectible")
    player:AnimateCollectible(POWER_TRAINING_ID, "Pickup", "PlayerPickupSparkle")
    
    local playerID = player:GetPlayerType()
    ConchBlessing.printDebug("Player ID: " .. tostring(playerID))
    
    local playerSave = SaveManager.GetRunSave(player)
    if not playerSave.powerTraining then
        playerSave.powerTraining = {}
    end
    
    local newIndex = #playerSave.powerTraining + 1
    ConchBlessing.printDebug("New index: " .. tostring(newIndex))
    
    if not ConchBlessing.powertraining.storedMultipliers then
        ConchBlessing.printDebug("Initializing storedMultipliers")
        ConchBlessing.powertraining.storedMultipliers = {}
    end
    if not ConchBlessing.powertraining.storedMultipliers[playerID] then
        ConchBlessing.printDebug("Initializing storedMultipliers for player " .. tostring(playerID))
        ConchBlessing.powertraining.storedMultipliers[playerID] = {}
    end
    
    -- Use math.random() per stat for independent randomness
    local function rollStat()
        local r = math.random()
        local span = ConchBlessing.powertraining.data.maxMultiplier - ConchBlessing.powertraining.data.minMultiplier
        local value = math.floor((r * span + ConchBlessing.powertraining.data.minMultiplier) * 100) / 100
        ConchBlessing.printDebug("Power Training rollStat r=" .. string.format("%.6f", r) .. ", value=" .. string.format("%.2f", value))
        return value
    end

    local newMultipliers = {
        speed = rollStat(),
        tears = rollStat(),
        damage = rollStat(),
        range = rollStat(),
        luck = rollStat()
    }
    
    ConchBlessing.printDebug("Generated multipliers: " .. json.encode(newMultipliers))
    
    ConchBlessing.printDebug("Attempting to save to SaveManager...")
    ConchBlessing.printDebug("SaveManager.GetRunSave result type: " .. type(playerSave))
    
    table.insert(playerSave.powerTraining, newMultipliers)
    ConchBlessing.printDebug("Data inserted into playerSave.powerTraining")
    
    ConchBlessing.printDebug("Power Training: Data saved to SaveManager! Use count: " .. #playerSave.powerTraining)
    
    ConchBlessing.printDebug("Forcing SaveManager.Save() to persist data...")
    SaveManager.Save()
    ConchBlessing.printDebug("SaveManager.Save() completed!")
    
    ConchBlessing.printDebug(string.format("Power Training #%d used: Speed=-%.2f Tears=%.2fx Damage=%.2fx Range=%.2fx Luck=%.2fx", 
        newIndex, ConchBlessing.powertraining.data.speedDecrease, newMultipliers.tears, newMultipliers.damage, newMultipliers.range, newMultipliers.luck))
    
    -- Calculate total accumulated multipliers for display
    local playerSave = SaveManager.GetRunSave(player)
    local totalSpeed = 1.0
    local totalTears = 1.0
    local totalDamage = 1.0
    local totalRange = 1.0
    local totalLuck = 1.0
    
    -- Multiply all previous multipliers
    for i = 1, #playerSave.powerTraining do
        local multipliers = playerSave.powerTraining[i]
        if multipliers then
            totalSpeed = totalSpeed * multipliers.speed
            totalTears = totalTears * multipliers.tears
            totalDamage = totalDamage * multipliers.damage
            totalRange = totalRange * multipliers.range
            totalLuck = totalLuck * multipliers.luck
        end
    end
    
    -- Update unified multipliers (current = last rolled, total = unified product)
    local uniqueKey = POWER_TRAINING_ID .. "_" .. newIndex
    if newIndex == 1 then
        ConchBlessing.stats.unifiedMultipliers:SetItemMultiplier(player, POWER_TRAINING_ID, "Tears", newMultipliers.tears, "Power Training #" .. newIndex)
        ConchBlessing.stats.unifiedMultipliers:SetItemMultiplier(player, POWER_TRAINING_ID, "Damage", newMultipliers.damage, "Power Training #" .. newIndex)
        ConchBlessing.stats.unifiedMultipliers:SetItemMultiplier(player, POWER_TRAINING_ID, "Range", newMultipliers.range, "Power Training #" .. newIndex)
        ConchBlessing.stats.unifiedMultipliers:SetItemMultiplier(player, POWER_TRAINING_ID, "Luck", newMultipliers.luck, "Power Training #" .. newIndex)
    else
        ConchBlessing.stats.unifiedMultipliers:SetItemAdditiveMultiplier(player, POWER_TRAINING_ID, "Tears", newMultipliers.tears, "Power Training #" .. newIndex)
        ConchBlessing.stats.unifiedMultipliers:SetItemAdditiveMultiplier(player, POWER_TRAINING_ID, "Damage", newMultipliers.damage, "Power Training #" .. newIndex)
        ConchBlessing.stats.unifiedMultipliers:SetItemAdditiveMultiplier(player, POWER_TRAINING_ID, "Range", newMultipliers.range, "Power Training #" .. newIndex)
        ConchBlessing.stats.unifiedMultipliers:SetItemAdditiveMultiplier(player, POWER_TRAINING_ID, "Luck", newMultipliers.luck, "Power Training #" .. newIndex)
    end
    
    SFXManager():Play(SoundEffect.SOUND_BATTERYCHARGE, 1.0, 0, false, 1.0, 0)
    
    player:AnimateCollectible(POWER_TRAINING_ID, "Drop", "PlayerPickupSparkle")
    
    ConchBlessing.printDebug("Power Training use effect completed! Use count: " .. newIndex)
    ConchBlessing.printDebug("=== Power Training onUseItem END ===")
    
    return { Discharge = true, Remove = false, ShowAnim = true }
end

ConchBlessing.powertraining.onEvaluateCache = function(_, player, cacheFlag)
    -- Prevent duplicate processing in the same frame
    local currentFrame = Game():GetFrameCount()
    local playerID = player:GetPlayerType()
    
    if ConchBlessing.powertraining._lastProcessedFrame == currentFrame and 
       ConchBlessing.powertraining._lastProcessedPlayer == playerID then
        return
    end
    
    -- Only process if this is actually a stat change for Power Training
    -- Don't process if this is just a cache refresh from other items
    if not ConchBlessing.powertraining._lastUseCount then
        ConchBlessing.powertraining._lastUseCount = {}
    end
    if not ConchBlessing.powertraining._lastUseCount[playerID] then
        ConchBlessing.powertraining._lastUseCount[playerID] = 0
    end
    
    -- Get current use count from SaveManager
    local playerSave = SaveManager.GetRunSave(player)
    local currentUseCount = playerSave and playerSave.powerTraining and #playerSave.powerTraining or 0
    
    -- Only process if use count actually changed
    if ConchBlessing.powertraining._lastUseCount[playerID] == currentUseCount then
        ConchBlessing.printDebug("Power Training: Use count unchanged (" .. currentUseCount .. "), skipping cache refresh")
        return
    end
    
    if cacheFlag == CacheFlag.CACHE_DAMAGE then
        ConchBlessing.printDebug("=== Power Training onEvaluateCache START ===")
        ConchBlessing.printDebug("cacheFlag: CACHE_DAMAGE")
    end
    
    if cacheFlag == CacheFlag.CACHE_DAMAGE then
        ConchBlessing.printDebug("Checking SaveManager data regardless of item ownership...")
    end
    
    if cacheFlag == CacheFlag.CACHE_DAMAGE then
        ConchBlessing.printDebug("Attempting to load from SaveManager...")
    end
    local playerSave = SaveManager.GetRunSave(player)
    
    if cacheFlag == CacheFlag.CACHE_DAMAGE then
        ConchBlessing.printDebug("SaveManager.GetRunSave result type: " .. type(playerSave))
        if playerSave then
            ConchBlessing.printDebug("playerSave.powerTraining exists: " .. tostring(playerSave.powerTraining ~= nil))
            if playerSave.powerTraining then
                ConchBlessing.printDebug("playerSave.powerTraining count: " .. tostring(#playerSave.powerTraining))
            end
        end
    end
    
    if not playerSave.powerTraining then
        if cacheFlag == CacheFlag.CACHE_DAMAGE then
            ConchBlessing.printDebug("No powerTraining data in playerSave, returning")
        end
        return
    end
    
    local useCount = #playerSave.powerTraining
    if useCount <= 0 then 
        if cacheFlag == CacheFlag.CACHE_DAMAGE then
            ConchBlessing.printDebug("useCount is 0, returning")
        end
        return 
    end
    
    if cacheFlag == CacheFlag.CACHE_DAMAGE and useCount ~= (ConchBlessing.powertraining._lastDebugUseCount or 0) then
        ConchBlessing.printDebug("Power Training: SaveManager data count (use count): " .. useCount)
        ConchBlessing.powertraining._lastDebugUseCount = useCount
    end
    
    local totalSpeed = 1.0
    local totalTears = 1.0
    local totalDamage = 1.0
    local totalRange = 1.0
    local totalLuck = 1.0
    
    for i = 1, useCount do
        local multipliers = playerSave.powerTraining[i]
        if multipliers then
            totalSpeed = totalSpeed * (multipliers.speed or 1.0)
            totalTears = totalTears * (multipliers.tears or 1.0)
            totalDamage = totalDamage * (multipliers.damage or 1.0)
            totalRange = totalRange * (multipliers.range or 1.0)
            totalLuck = totalLuck * (multipliers.luck or 1.0)
        end
    end
    
    totalSpeed = math.max(ConchBlessing.powertraining.data.minMultiplier, totalSpeed)
    totalTears = math.max(ConchBlessing.powertraining.data.minMultiplier, totalTears)
    totalDamage = math.max(ConchBlessing.powertraining.data.minMultiplier, totalDamage)
    totalRange = math.max(ConchBlessing.powertraining.data.minMultiplier, totalRange)
    totalLuck = math.max(ConchBlessing.powertraining.data.minMultiplier, totalLuck)
    
    if cacheFlag == CacheFlag.CACHE_DAMAGE and useCount ~= (ConchBlessing.powertraining._lastFinalDebugUseCount or 0) then
        local speedDecrease = ConchBlessing.powertraining.data.speedDecrease * useCount
        ConchBlessing.printDebug(string.format("Power Training Final (x%d uses): Speed=-%.2f Tears=%.2fx Damage=%.2fx Range=%.2fx Luck=%.2fx", 
            useCount, speedDecrease, totalTears, totalDamage, totalRange, totalLuck))
        ConchBlessing.powertraining._lastFinalDebugUseCount = useCount
    end
    
    if cacheFlag == CacheFlag.CACHE_DAMAGE then
        -- unified system will apply via central handler
    end
    
    if cacheFlag == CacheFlag.CACHE_FIREDELAY then
        -- unified system will apply via central handler
    end
    
    if cacheFlag == CacheFlag.CACHE_SPEED then
        local speedDecrease = ConchBlessing.powertraining.data.speedDecrease * useCount
        ConchBlessing.stats.speed.applyAddition(player, -speedDecrease, ConchBlessing.powertraining.data.minMultiplier)
    end
    
    if cacheFlag == CacheFlag.CACHE_RANGE then
        -- unified system will apply via central handler
    end
    
    if cacheFlag == CacheFlag.CACHE_LUCK then
        -- unified system will apply via central handler
    end
    
    -- Display handled by unified system
    
    -- Mark this frame as processed to prevent duplicate calls
    ConchBlessing.powertraining._lastProcessedFrame = currentFrame
    ConchBlessing.powertraining._lastProcessedPlayer = playerID
    
    -- Record the use count that was processed
    ConchBlessing.powertraining._lastUseCount[playerID] = currentUseCount
end

-- initialize data when game started
ConchBlessing.powertraining.onGameStarted = function(_)
    ConchBlessing.printDebug("=== Power Training onGameStarted START ===")
    ConchBlessing.printDebug("Power Training: Game started, attempting to restore previous stats...")
    
    -- SaveManager automatically loads data, no manual loading needed
    
    ConchBlessing.printDebug("SaveManager.VERSION: " .. tostring(SaveManager.VERSION))
    ConchBlessing.printDebug("SaveManager.Debug: " .. tostring(SaveManager.Debug))
    
    local player = Isaac.GetPlayer(0)
    if player then
        ConchBlessing.printDebug("Player found, attempting to restore stats from SaveManager...")
        
        local playerSave = SaveManager.GetRunSave(player)
        if playerSave and playerSave.powerTraining then
            local useCount = #playerSave.powerTraining
            ConchBlessing.printDebug("Found saved data with use count: " .. tostring(useCount))
            
            if useCount > 0 then
                local totalSpeed = 1.0
                local totalTears = 1.0
                local totalDamage = 1.0
                local totalRange = 1.0
                local totalLuck = 1.0
                
                for i = 1, useCount do
                    local multipliers = playerSave.powerTraining[i]
                    if multipliers then
                        totalSpeed = totalSpeed * (multipliers.speed or 1.0)
                        totalTears = totalTears * (multipliers.tears or 1.0)
                        totalDamage = totalDamage * (multipliers.damage or 1.0)
                        totalRange = totalRange * (multipliers.range or 1.0)
                        totalLuck = totalLuck * (multipliers.luck or 1.0)
                    end
                end
                
                totalSpeed = math.max(ConchBlessing.powertraining.data.minMultiplier, totalSpeed)
                totalTears = math.max(ConchBlessing.powertraining.data.minMultiplier, totalTears)
                totalDamage = math.max(ConchBlessing.powertraining.data.minMultiplier, totalDamage)
                totalRange = math.max(ConchBlessing.powertraining.data.minMultiplier, totalRange)
                totalLuck = math.max(ConchBlessing.powertraining.data.minMultiplier, totalLuck)
                
                local speedDecrease = ConchBlessing.powertraining.data.speedDecrease * useCount
                ConchBlessing.printDebug(string.format("Calculated final multipliers: Speed=-%.2f Tears=%.2fx Damage=%.2fx Range=%.2fx Luck=%.2fx", 
                    speedDecrease, totalTears, totalDamage, totalRange, totalLuck))
                
                ConchBlessing.stats.speed.applyAddition(player, -speedDecrease, ConchBlessing.powertraining.data.minMultiplier)
                
                -- Update unified system from saved data: first entry multiplier, rest additive
                for i = 1, useCount do
                    local multipliers = playerSave.powerTraining[i]
                    if i == 1 then
                        ConchBlessing.stats.unifiedMultipliers:SetItemMultiplier(player, POWER_TRAINING_ID, "Tears", multipliers.tears or 1.0, "Power Training #1")
                        ConchBlessing.stats.unifiedMultipliers:SetItemMultiplier(player, POWER_TRAINING_ID, "Damage", multipliers.damage or 1.0, "Power Training #1")
                        ConchBlessing.stats.unifiedMultipliers:SetItemMultiplier(player, POWER_TRAINING_ID, "Range", multipliers.range or 1.0, "Power Training #1")
                        ConchBlessing.stats.unifiedMultipliers:SetItemMultiplier(player, POWER_TRAINING_ID, "Luck", multipliers.luck or 1.0, "Power Training #1")
                    else
                        ConchBlessing.stats.unifiedMultipliers:SetItemAdditiveMultiplier(player, POWER_TRAINING_ID, "Tears", multipliers.tears or 1.0, "Power Training #" .. i)
                        ConchBlessing.stats.unifiedMultipliers:SetItemAdditiveMultiplier(player, POWER_TRAINING_ID, "Damage", multipliers.damage or 1.0, "Power Training #" .. i)
                        ConchBlessing.stats.unifiedMultipliers:SetItemAdditiveMultiplier(player, POWER_TRAINING_ID, "Range", multipliers.range or 1.0, "Power Training #" .. i)
                        ConchBlessing.stats.unifiedMultipliers:SetItemAdditiveMultiplier(player, POWER_TRAINING_ID, "Luck", multipliers.luck or 1.0, "Power Training #" .. i)
                    end
                end
            else
                ConchBlessing.printDebug("No saved data found, starting with base stats")
            end
        else
            ConchBlessing.printDebug("No SaveManager data found")
        end
    else
        ConchBlessing.printDebug("No player found on game start")
    end
    
    ConchBlessing.printDebug("Power Training: Data initialization completed")
    ConchBlessing.printDebug("=== Power Training onGameStarted END ===")
end

-- upgrade related functions
ConchBlessing.powertraining.onBeforeChange = function(upgradePos, pickup, itemData)
    return ConchBlessing.template.positive.onBeforeChange(upgradePos, pickup, ConchBlessing.powertraining.data)
end

ConchBlessing.powertraining.onAfterChange = function(upgradePos, pickup, itemData)
    return ConchBlessing.template.positive.onAfterChange(upgradePos, pickup, ConchBlessing.powertraining.data)
end

ConchBlessing.powertraining.onUpdate = function(_)
    ConchBlessing.template.onUpdate(ConchBlessing.powertraining.data)
end 