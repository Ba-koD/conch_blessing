ConchBlessing.injectablsteroids = {}

local INJECTABLE_STEROIDS_ID = Isaac.GetItemIdByName("Injectable Steroids")

-- data table for upgrade system
ConchBlessing.injectablsteroids.data = {
    minMultiplier = 0.5,
    maxMultiplier = 2.0,
    speedDecrease = 0,
    instantDeathPercent = 1  -- 1% chance of instant death when used
}

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

ConchBlessing.injectablsteroids.onUseItem = function(player, collectibleID, useFlags, activeSlot, customVarData)
    ConchBlessing.printDebug("=== Injectable Steroids onUseItem START ===")
    ConchBlessing.printDebug("collectibleID: " .. tostring(collectibleID))
    ConchBlessing.printDebug("INJECTABLE_STEROIDS_ID: " .. tostring(INJECTABLE_STEROIDS_ID))
    
    if collectibleID ~= INJECTABLE_STEROIDS_ID then
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
    player:AnimateCollectible(INJECTABLE_STEROIDS_ID, "Pickup", "PlayerPickupSparkle")
    
    -- Check for instant death chance
    local instantDeathChance = ConchBlessing.injectablsteroids.data.instantDeathPercent
    ConchBlessing.printDebug("Instant death chance: " .. tostring(instantDeathChance) .. "%")
    
    if instantDeathChance > 0 then
        local deathRoll = math.random(1, 100)
        ConchBlessing.printDebug("Death roll: " .. tostring(deathRoll) .. " (need <= " .. tostring(instantDeathChance) .. " for death)")
        
        if deathRoll <= instantDeathChance then
            ConchBlessing.printDebug("INSTANT DEATH TRIGGERED! Player dies from Injectable Steroids overdose")
            player:TakeDamage(999, DamageFlag.DAMAGE_NO_PENALTIES, EntityRef(player), 0)
            return { Discharge = true, Remove = false, ShowAnim = true }
        else
            ConchBlessing.printDebug("Instant death avoided, continuing with normal effect")
        end
    end
    
    local playerID = player:GetPlayerType()
    ConchBlessing.printDebug("Player ID: " .. tostring(playerID))
    
    local playerSave = SaveManager.GetRunSave(player)
    if not playerSave.injectableSteroids then
        playerSave.injectableSteroids = {}
    end
    
    local newIndex = #playerSave.injectableSteroids + 1
    ConchBlessing.printDebug("New index: " .. tostring(newIndex))
    
    if not ConchBlessing.injectablsteroids.storedMultipliers then
        ConchBlessing.printDebug("Initializing storedMultipliers")
        ConchBlessing.injectablsteroids.storedMultipliers = {}
    end
    if not ConchBlessing.injectablsteroids.storedMultipliers[playerID] then
        ConchBlessing.printDebug("Initializing storedMultipliers for player " .. tostring(playerID))
        ConchBlessing.injectablsteroids.storedMultipliers[playerID] = {}
    end
    
    local rng = RNG()
    local gameSeed = Game():GetSeeds():GetStartSeedString()
    local gameSeedHash = 0
    
    for j = 1, #gameSeed do
        local char = string.byte(gameSeed, j)
        gameSeedHash = gameSeedHash + char * (j * 31 + char)
    end
    
    local combinedSeed = newIndex + gameSeedHash
    
    ConchBlessing.printDebug("Injectable Steroids RNG Debug:")
    ConchBlessing.printDebug("  Game Seed: " .. gameSeed)
    ConchBlessing.printDebug("  Game Seed Hash: " .. gameSeedHash)
    ConchBlessing.printDebug("  New Index: " .. newIndex)
    ConchBlessing.printDebug("  Combined Seed: " .. combinedSeed)
    
    -- Use math.random() for independent randomness per stat (requested)
    local function rollStat()
        local r = math.random()
        local span = ConchBlessing.injectablsteroids.data.maxMultiplier - ConchBlessing.injectablsteroids.data.minMultiplier
        local value = math.floor((r * span + ConchBlessing.injectablsteroids.data.minMultiplier) * 100) / 100
        ConchBlessing.printDebug("Injectable Steroids: rollStat() r=" .. string.format("%.6f", r) .. ", value=" .. string.format("%.2f", value))
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
    local playerSave = SaveManager.GetRunSave(player)
    ConchBlessing.printDebug("SaveManager.GetRunSave result type: " .. type(playerSave))
    
    if not playerSave.injectableSteroids then
        ConchBlessing.printDebug("Initializing injectableSteroids in playerSave")
        playerSave.injectableSteroids = {}
    end
    
    table.insert(playerSave.injectableSteroids, newMultipliers)
    ConchBlessing.printDebug("Data inserted into playerSave.injectableSteroids")
    
    ConchBlessing.printDebug("Injectable Steroids: Data saved to SaveManager! Use count: " .. #playerSave.injectableSteroids)
    
    ConchBlessing.printDebug("Forcing SaveManager.Save() to persist data...")
    SaveManager.Save()
    ConchBlessing.printDebug("SaveManager.Save() completed!")
    
    ConchBlessing.printDebug(string.format("Injectable Steroids #%d used: Speed=-%.2f Tears=%.2fx Damage=%.2fx Range=%.2fx Luck=%.2fx", 
        newIndex, ConchBlessing.injectablsteroids.data.speedDecrease, newMultipliers.tears, newMultipliers.damage, newMultipliers.range, newMultipliers.luck))
    
    -- Update unified multiplier system with the new multipliers
    local uniqueKey = INJECTABLE_STEROIDS_ID .. "_" .. newIndex
    -- Always treat as additive multiplier stacking
    ConchBlessing.stats.unifiedMultipliers:SetItemAdditiveMultiplier(
        player, INJECTABLE_STEROIDS_ID, "Tears", newMultipliers.tears, "Injectable Steroids #" .. newIndex
    )
    ConchBlessing.stats.unifiedMultipliers:SetItemAdditiveMultiplier(
        player, INJECTABLE_STEROIDS_ID, "Damage", newMultipliers.damage, "Injectable Steroids #" .. newIndex
    )
    ConchBlessing.stats.unifiedMultipliers:SetItemAdditiveMultiplier(
        player, INJECTABLE_STEROIDS_ID, "Range", newMultipliers.range, "Injectable Steroids #" .. newIndex
    )
    ConchBlessing.stats.unifiedMultipliers:SetItemAdditiveMultiplier(
        player, INJECTABLE_STEROIDS_ID, "Luck", newMultipliers.luck, "Injectable Steroids #" .. newIndex
    )
    
    -- Save unified multipliers to SaveManager
    ConchBlessing.stats.unifiedMultipliers:SaveToSaveManager(player)
    
    SFXManager():Play(SoundEffect.SOUND_ISAAC_HURT_GRUNT, 1.0, 0, false, 1.0, 0)
    
    if not ConchBlessing.injectablsteroids._yellowIntensity then
        ConchBlessing.printDebug("Initializing _yellowIntensity")
        ConchBlessing.injectablsteroids._yellowIntensity = 0
    end
    
    ConchBlessing.injectablsteroids._yellowIntensity = ConchBlessing.injectablsteroids._yellowIntensity + 0.2
    
    player:AnimateCollectible(INJECTABLE_STEROIDS_ID, "Drop", "PlayerPickupSparkle")
    
    ConchBlessing.printDebug("Injectable Steroids use effect completed! Use count: " .. newIndex)
    
    -- Notify Oral Steroids that Injectable was just used
    if ConchBlessing.oralsteroids then
        ConchBlessing.oralsteroids._lastInjectableUseFrame = Game():GetFrameCount()
        ConchBlessing.printDebug("Injectable Steroids: Notified Oral Steroids of recent use (frame " .. Game():GetFrameCount() .. ")")
    end
    
    ConchBlessing.printDebug("=== Injectable Steroids onUseItem END ===")
    
    return { Discharge = true, Remove = false, ShowAnim = true }
end


ConchBlessing.injectablsteroids.onEvaluateCache = function(_, player, cacheFlag)
    -- Prevent duplicate processing in the same frame
    local currentFrame = Game():GetFrameCount()
    local playerID = player:GetPlayerType()
    
    if ConchBlessing.injectablsteroids._lastProcessedFrame == currentFrame and 
       ConchBlessing.injectablsteroids._lastProcessedPlayer == playerID then
        return
    end
    
    -- Only process if this is actually a stat change for Injectable Steroids
    -- Don't process if this is just a cache refresh from other items
    if not ConchBlessing.injectablsteroids._lastUseCount then
        ConchBlessing.injectablsteroids._lastUseCount = {}
    end
    if not ConchBlessing.injectablsteroids._lastUseCount[playerID] then
        ConchBlessing.injectablsteroids._lastUseCount[playerID] = 0
    end
    
    -- Get current use count from SaveManager
    local playerSave = SaveManager.GetRunSave(player)
    local currentUseCount = playerSave and playerSave.injectableSteroids and #playerSave.injectableSteroids or 0
    
    -- Only process if use count actually changed
    if ConchBlessing.injectablsteroids._lastUseCount[playerID] == currentUseCount then
        ConchBlessing.printDebug("Injectable Steroids: Use count unchanged (" .. currentUseCount .. "), skipping cache refresh")
        return
    end
    
    if cacheFlag == CacheFlag.CACHE_DAMAGE then
        ConchBlessing.printDebug("=== Injectable Steroids onEvaluateCache START ===")
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
            ConchBlessing.printDebug("playerSave.injectableSteroids exists: " .. tostring(playerSave.injectableSteroids ~= nil))
            if playerSave.injectableSteroids then
                ConchBlessing.printDebug("playerSave.injectableSteroids count: " .. tostring(#playerSave.injectableSteroids))
            end
        end
    end
    
    if not playerSave.injectableSteroids then
        if cacheFlag == CacheFlag.CACHE_DAMAGE then
            ConchBlessing.printDebug("No injectableSteroids data in playerSave, returning")
        end
        return
    end
    
    local useCount = #playerSave.injectableSteroids
    if useCount <= 0 then 
        if cacheFlag == CacheFlag.CACHE_DAMAGE then
            ConchBlessing.printDebug("useCount is 0, returning")
        end
        return 
    end
    
    if cacheFlag == CacheFlag.CACHE_DAMAGE and useCount ~= (ConchBlessing.injectablsteroids._lastDebugUseCount or 0) then
        ConchBlessing.printDebug("Injectable Steroids: SaveManager data count (use count): " .. useCount)
        ConchBlessing.injectablsteroids._lastDebugUseCount = useCount
    end
    
    local totalSpeed = 1.0
    local totalTears = 1.0
    local totalDamage = 1.0
    local totalRange = 1.0
    local totalLuck = 1.0
    
    for i = 1, useCount do
        local multipliers = playerSave.injectableSteroids[i]
        if multipliers then
            totalSpeed = totalSpeed * multipliers.speed
            totalTears = totalTears * multipliers.tears
            totalDamage = totalDamage * multipliers.damage
            totalRange = totalRange * multipliers.range
            totalLuck = totalLuck * multipliers.luck
        end
    end
    
    totalSpeed = math.max(ConchBlessing.injectablsteroids.data.minMultiplier, totalSpeed)
    totalTears = math.max(ConchBlessing.injectablsteroids.data.minMultiplier, totalTears)
    totalDamage = math.max(ConchBlessing.injectablsteroids.data.minMultiplier, totalDamage)
    totalRange = math.max(ConchBlessing.injectablsteroids.data.minMultiplier, totalRange)
    totalLuck = math.max(ConchBlessing.injectablsteroids.data.minMultiplier, totalLuck)
    
    if cacheFlag == CacheFlag.CACHE_DAMAGE and useCount ~= (ConchBlessing.injectablsteroids._lastFinalDebugUseCount or 0) then
        local speedDecrease = ConchBlessing.injectablsteroids.data.speedDecrease * useCount
        ConchBlessing.printDebug(string.format("Injectable Steroids Final (x%d uses): Speed=-%.2f Tears=%.2fx Damage=%.2fx Range=%.2fx Luck=%.2fx", 
            useCount, speedDecrease, totalTears, totalDamage, totalRange, totalLuck))
        ConchBlessing.injectablsteroids._lastFinalDebugUseCount = useCount
    end
    
    if cacheFlag == CacheFlag.CACHE_FIREDELAY then
        -- unified system will apply via central handler
    end
    
    if cacheFlag == CacheFlag.CACHE_DAMAGE then
        -- unified system will apply via central handler
    end
    
    if cacheFlag == CacheFlag.CACHE_SPEED then
        local speedDecrease = ConchBlessing.injectablsteroids.data.speedDecrease * useCount
        ConchBlessing.stats.speed.applyAddition(player, -speedDecrease, ConchBlessing.injectablsteroids.data.minMultiplier)
    end
    
    if cacheFlag == CacheFlag.CACHE_RANGE then
        -- unified system will apply via central handler
    end
    
    if cacheFlag == CacheFlag.CACHE_LUCK then
        -- unified system will apply via central handler
    end
    
    -- Mark this frame as processed to prevent duplicate calls
    ConchBlessing.injectablsteroids._lastProcessedFrame = currentFrame
    ConchBlessing.injectablsteroids._lastProcessedPlayer = playerID
    
    -- Record the use count that was processed
    ConchBlessing.injectablsteroids._lastUseCount[playerID] = currentUseCount
end

-- initialize data when game started
ConchBlessing.injectablsteroids.onGameStarted = function(_)
    ConchBlessing.printDebug("=== Injectable Steroids onGameStarted START ===")
    ConchBlessing.printDebug("Injectable Steroids: Game started, attempting to restore previous stats...")
    
    -- SaveManager automatically loads data, no manual loading needed
    ConchBlessing.injectablsteroids._yellowIntensity = 0
    
    ConchBlessing.printDebug("SaveManager.VERSION: " .. tostring(SaveManager.VERSION))
    ConchBlessing.printDebug("SaveManager.Debug: " .. tostring(SaveManager.Debug))
    
    local player = Isaac.GetPlayer(0)
    if player then
        ConchBlessing.printDebug("Player found, attempting to restore stats from SaveManager...")
        
        local playerSave = SaveManager.GetRunSave(player)
        local haveArrays = playerSave and playerSave.injectableSteroids
        local haveUnified = playerSave and playerSave.unifiedMultipliers
        if haveUnified then
            ConchBlessing.stats.unifiedMultipliers:LoadFromSaveManager(player)
            ConchBlessing.printDebug("Injectable Steroids: Unified multipliers loaded from SaveManager")
        elseif haveArrays and #haveArrays > 0 then
            -- Reconstruct unified from arrays (first-time migration) with additive-mult stacking
            for i = 1, #haveArrays do
                local m = haveArrays[i]
                ConchBlessing.stats.unifiedMultipliers:SetItemAdditiveMultiplier(player, INJECTABLE_STEROIDS_ID, "Tears", m.tears or 1.0, "Injectable Steroids #" .. i)
                ConchBlessing.stats.unifiedMultipliers:SetItemAdditiveMultiplier(player, INJECTABLE_STEROIDS_ID, "Damage", m.damage or 1.0, "Injectable Steroids #" .. i)
                ConchBlessing.stats.unifiedMultipliers:SetItemAdditiveMultiplier(player, INJECTABLE_STEROIDS_ID, "Range", m.range or 1.0, "Injectable Steroids #" .. i)
                ConchBlessing.stats.unifiedMultipliers:SetItemAdditiveMultiplier(player, INJECTABLE_STEROIDS_ID, "Luck", m.luck or 1.0, "Injectable Steroids #" .. i)
            end
            ConchBlessing.stats.unifiedMultipliers:SaveToSaveManager(player)
            ConchBlessing.printDebug("Injectable Steroids: Unified multipliers reconstructed from arrays and saved")
        else
            ConchBlessing.printDebug("No SaveManager data found")
        end
    else
        ConchBlessing.printDebug("No player found on game start")
    end
    
    ConchBlessing.printDebug("Injectable Steroids: Data initialization completed")
    ConchBlessing.printDebug("=== Injectable Steroids onGameStarted END ===")
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
    
    local slots = {ActiveSlot.SLOT_PRIMARY, ActiveSlot.SLOT_SECONDARY, ActiveSlot.SLOT_POCKET, ActiveSlot.SLOT_POCKET2}
    
    for _, slot in ipairs(slots) do
        local activeItem = player:GetActiveItem(slot)
        if activeItem == INJECTABLE_STEROIDS_ID then
            player:SetActiveCharge(1, slot)
            ConchBlessing.printDebug(string.format("Injectable Steroids charge restored in slot %d", slot))
        end
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

-- Register PRE_DATA_SAVE sanitizer for this item's run data only
do
    local sm = SaveManager
    local mod = ConchBlessing and ConchBlessing.originalMod
    if sm and mod and mod.__SAVEMANAGER_UNIQUE_KEY and sm.SaveCallbacks then
        local callbackKey = mod.__SAVEMANAGER_UNIQUE_KEY .. sm.SaveCallbacks.PRE_DATA_SAVE
        mod:AddCallback(callbackKey, function(saveData)
            if saveData and saveData.game and saveData.game.run then
                for _, playerRun in pairs(saveData.game.run) do
                    local arr = playerRun and playerRun.injectableSteroids
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
                        playerRun.injectableSteroids = compacted
                    end
                end
            end
            if ConchBlessing and ConchBlessing.Config and ConchBlessing.Config.debugMode then
                ConchBlessing.printDebug("[InjectableSteroids] PRE_DATA_SAVE sanitized injectableSteroids array")
            end
            return saveData
        end)
    end
end