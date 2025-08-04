ConchBlessing.liveeye = {}

-- Live Eye effect variables
ConchBlessing.liveeye.data = {
    damageMultiplier = 1.0,  -- default damage multiplier (1.0)
    maxDamageMultiplier = 3.0,  -- max damage multiplier (3.0)
    minDamageMultiplier = 0.5,  -- min damage multiplier (0.5)
    hitMultiplierIncrease = 0.1,  -- hit multiplier increase
    missMultiplierDecrease = 0.15,  -- miss multiplier decrease
    trackedTears = {},  -- tracked tears with lifetime
    tearLifetime = 90,  -- 1.5 seconds at 60fps
}

-- on pickup
ConchBlessing.liveeye.onPickup = function(player, collectibleType, rng)
    ConchBlessing.printDebug("Live Eye item picked up!")
    -- add damage cache flag
    player:AddCacheFlags(CacheFlag.CACHE_DAMAGE)
    player:EvaluateItems()
end

-- on use (passive item but just in case)
ConchBlessing.liveeye.onUse = function(collectibleType, rng, player, useFlags, activeSlot, customVarData)
    ConchBlessing.printDebug("Live Eye used!")
    return { Discharge = false, Remove = false, ShowAnim = false }
end

-- calculate damage multiplier
ConchBlessing.liveeye.onEvaluateCache = function(player, cacheFlag)
    if cacheFlag == CacheFlag.CACHE_DAMAGE then
        if player:HasCollectible(Isaac.GetItemIdByName("Live Eye")) then
            local baseDamage = player.Damage
            -- calculate original damage before applying multiplier
            local originalDamage = baseDamage / ConchBlessing.liveeye.data.damageMultiplier
            -- apply new multiplier
            player.Damage = originalDamage * ConchBlessing.liveeye.data.damageMultiplier
            
            ConchBlessing.printDebug(string.format("Live Eye damage multiplier: %.2fx (damage: %.2f)", 
                ConchBlessing.liveeye.data.damageMultiplier, player.Damage))
        end
    end
end

-- handle hit
ConchBlessing.liveeye.handleHit = function()
    local oldMultiplier = ConchBlessing.liveeye.data.damageMultiplier
    ConchBlessing.liveeye.data.damageMultiplier = math.min(
        ConchBlessing.liveeye.data.damageMultiplier + ConchBlessing.liveeye.data.hitMultiplierIncrease,
        ConchBlessing.liveeye.data.maxDamageMultiplier
    )
    
    local player = Isaac.GetPlayer(0)
    if player then
        player:AddCacheFlags(CacheFlag.CACHE_DAMAGE)
        player:EvaluateItems()
    end
    
    ConchBlessing.printDebug(string.format("Live Eye: hit! multiplier %.2f -> %.2f", 
        oldMultiplier, ConchBlessing.liveeye.data.damageMultiplier))
end

-- handle miss
ConchBlessing.liveeye.handleMiss = function()
    local oldMultiplier = ConchBlessing.liveeye.data.damageMultiplier
    ConchBlessing.liveeye.data.damageMultiplier = math.max(
        ConchBlessing.liveeye.data.damageMultiplier - ConchBlessing.liveeye.data.missMultiplierDecrease,
        ConchBlessing.liveeye.data.minDamageMultiplier
    )
    
    local player = Isaac.GetPlayer(0)
    if player then
        player:AddCacheFlags(CacheFlag.CACHE_DAMAGE)
        player:EvaluateItems()
    end
    
    ConchBlessing.printDebug(string.format("Live Eye: miss! multiplier %.2f -> %.2f", 
        oldMultiplier, ConchBlessing.liveeye.data.damageMultiplier))
end

-- start tracking when tear is fired (MC_POST_FIRE_TEAR)
ConchBlessing.liveeye.onFireTear = function(tear)
    local player = Isaac.GetPlayer(0)
    
    if player and player:HasCollectible(Isaac.GetItemIdByName("Live Eye")) then
        -- check if the tear is from the player
        if tear.Parent and tear.Parent:ToPlayer() then
            -- generate unique ID using tear index and frame
            local tearId = tostring(tear.Index) .. "_" .. tostring(Game():GetFrameCount())
            
            -- store tear tracking data
            ConchBlessing.liveeye.data.trackedTears[tearId] = {
                tear = tear,
                frameCount = Game():GetFrameCount(),
                hit = false
            }
            
            ConchBlessing.printDebug("Live Eye: tear tracking started (ID: " .. tearId .. ")")
        end
    end
end

-- track tear collision with enemies (MC_PRE_TEAR_COLLISION)
ConchBlessing.liveeye.onTearCollision = function(tear, collider, low)
    local player = Isaac.GetPlayer(0)
    
    if player and player:HasCollectible(Isaac.GetItemIdByName("Live Eye")) then
        -- check if tear hits an enemy
        if collider and collider:IsEnemy() and tear.Parent and tear.Parent:ToPlayer() then
            -- find and mark this tear as hit
            local tearId = tostring(tear.Index) .. "_"
            
            for id, trackData in pairs(ConchBlessing.liveeye.data.trackedTears) do
                if string.find(id, tearId) and not trackData.hit then
                    trackData.hit = true
                    ConchBlessing.liveeye.handleHit()
                    ConchBlessing.printDebug("Live Eye: tear hit enemy!")
                    break
                end
            end
        end
    end
    
    -- don't prevent collision
    return nil
end

-- update every frame to check for missed tears (MC_POST_UPDATE)
ConchBlessing.liveeye.onUpdate = function()
    local player = Isaac.GetPlayer(0)
    
    if player and player:HasCollectible(Isaac.GetItemIdByName("Live Eye")) then
        local currentFrame = Game():GetFrameCount()
        local toRemove = {}
        
        -- check for missed tears (tears that exist too long without hitting)
        for tearId, trackData in pairs(ConchBlessing.liveeye.data.trackedTears) do
            if not trackData.hit then
                -- check if tear still exists
                if not trackData.tear or not trackData.tear:Exists() then
                    -- tear disappeared without hitting - count as miss
                    ConchBlessing.liveeye.handleMiss()
                    table.insert(toRemove, tearId)
                    ConchBlessing.printDebug("Live Eye: tear disappeared (miss)")
                elseif (currentFrame - trackData.frameCount) >= ConchBlessing.liveeye.data.tearLifetime then
                    -- tear lived too long - count as miss
                    ConchBlessing.liveeye.handleMiss()
                    table.insert(toRemove, tearId)
                    ConchBlessing.printDebug("Live Eye: tear timeout (miss)")
                end
            else
                -- tear already hit, remove from tracking
                table.insert(toRemove, tearId)
            end
        end
        
        -- cleanup old tracking data
        for _, tearId in ipairs(toRemove) do
            ConchBlessing.liveeye.data.trackedTears[tearId] = nil
        end
        
        -- also cleanup very old entries (over 5 seconds)
        for tearId, trackData in pairs(ConchBlessing.liveeye.data.trackedTears) do
            if (currentFrame - trackData.frameCount) >= 300 then  -- 5 seconds
                ConchBlessing.liveeye.data.trackedTears[tearId] = nil
            end
        end
    end
end

-- initialize data when game starts
ConchBlessing.liveeye.onGameStarted = function()
    ConchBlessing.liveeye.data.damageMultiplier = 1.0
    ConchBlessing.liveeye.data.trackedTears = {}
    ConchBlessing.printDebug("Live Eye data initialized!")
    
    -- apply item effect when game starts
    local player = Isaac.GetPlayer(0)
    if player and player:HasCollectible(Isaac.GetItemIdByName("Live Eye")) then
        player:AddCacheFlags(CacheFlag.CACHE_DAMAGE)
        player:EvaluateItems()
    end
end