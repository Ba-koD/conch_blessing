ConchBlessing.liveeye = {}

-- Live Eye effect variables
ConchBlessing.liveeye.data = {
    damageMultiplier = 1.0,  -- default damage multiplier (1.0)
    maxDamageMultiplier = 3.0,  -- max damage multiplier (3.0)
    minDamageMultiplier = 0.5,  -- min damage multiplier (0.5)
    hitMultiplierIncrease = 0.1,  -- hit multiplier increase
    missMultiplierDecrease = 0.15,  -- miss multiplier decrease
    trackedTears = {},  -- tracked tears with lifetime
}

-- on pickup
ConchBlessing.liveeye.onPickup = function(player, collectibleType, rng)
    ConchBlessing.printDebug("Live Eye item picked up!")
    -- add damage cache flag
    player:AddCacheFlags(CacheFlag.CACHE_DAMAGE)
    player:EvaluateItems()
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
        -- check if this is a player's tear hitting an enemy
        if tear.Parent and tear.Parent:ToPlayer() and collider and collider:IsEnemy() then
            -- find and mark this tear as hit
            local tearId = tostring(tear.Index) .. "_"
            
            for id, trackData in pairs(ConchBlessing.liveeye.data.trackedTears) do
                if string.find(id, tearId) and not trackData.hit then
                    trackData.hit = true
                    ConchBlessing.liveeye.handleHit()
                    ConchBlessing.printDebug("Live Eye: player tear hit enemy! (HIT)")
                    break
                end
            end
        end
        
        -- check if player's tear hits wall or other obstacles (miss)
        if tear.Parent and tear.Parent:ToPlayer() and collider and not collider:IsEnemy() then
            local tearId = tostring(tear.Index) .. "_"
            
            for id, trackData in pairs(ConchBlessing.liveeye.data.trackedTears) do
                if string.find(id, tearId) and not trackData.hit then
                    -- tear hit wall or obstacle - count as miss
                    trackData.hit = true  -- mark as processed to avoid double counting
                    ConchBlessing.liveeye.handleMiss()
                    ConchBlessing.printDebug("Live Eye: player tear hit wall/obstacle (MISS)")
                    break
                end
            end
        end
    end
    
    -- don't prevent collision
    return nil
end

-- handle tear removal (MC_POST_ENTITY_REMOVE)
ConchBlessing.liveeye.onTearRemoved = function(entity)
    local player = Isaac.GetPlayer(0)
    
    if player and player:HasCollectible(Isaac.GetItemIdByName("Live Eye")) then
        -- check if this is a tear from the player
        if entity.Type == EntityType.ENTITY_TEAR and entity.Parent and entity.Parent:ToPlayer() then
            local tearId = tostring(entity.Index) .. "_"
            
            -- check if this tear was tracked and didn't hit
            for id, trackData in pairs(ConchBlessing.liveeye.data.trackedTears) do
                if string.find(id, tearId) and not trackData.hit then
                    -- tear was removed without hitting - count as miss
                    ConchBlessing.liveeye.handleMiss()
                    ConchBlessing.liveeye.data.trackedTears[id] = nil
                    ConchBlessing.printDebug("Live Eye: tear removed without hitting (miss)")
                    break
                end
            end
        end
    end
end

-- update every frame to cleanup old tracking data (MC_POST_UPDATE)
ConchBlessing.liveeye.onUpdate = function()
    local player = Isaac.GetPlayer(0)
    
    if player and player:HasCollectible(Isaac.GetItemIdByName("Live Eye")) then
        local toRemove = {}
        
        -- cleanup old tracking data (only remove tears that already hit)
        for tearId, trackData in pairs(ConchBlessing.liveeye.data.trackedTears) do
            if trackData.hit then
                -- tear already hit, remove from tracking
                table.insert(toRemove, tearId)
            end
        end
        
        -- cleanup old entries
        for _, tearId in ipairs(toRemove) do
            ConchBlessing.liveeye.data.trackedTears[tearId] = nil
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