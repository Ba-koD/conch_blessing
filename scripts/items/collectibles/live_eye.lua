ConchBlessing.liveeye = {}

ConchBlessing.liveeye.data = {
    damageMultiplier = 1.0,
    maxDamageMultiplier = 3.0,
    minDamageMultiplier = 0.75,
    hitMultiplierIncrease = 0.1,
    missMultiplierDecrease = 0.15,
}

local LIVE_EYE_ID = Isaac.GetItemIdByName("Live Eye")

local function getAboveOneGlowRatio()
    local maxM = ConchBlessing.liveeye.data.maxDamageMultiplier
    local curM = ConchBlessing.liveeye.data.damageMultiplier
    if maxM <= 1.0 then
        return 0
    end
    if curM <= 1.0 then
        return 0
    end
    local t = (curM - 1.0) / (maxM - 1.0)
    if t < 0 then return 0 end
    if t > 1 then return 1 end
    return t
end

local function getBelowOneGlowRatio()
    local minM = ConchBlessing.liveeye.data.minDamageMultiplier
    local curM = ConchBlessing.liveeye.data.damageMultiplier
    if curM >= 1.0 then
        return 0
    end
    if 1.0 <= minM then
        return 0
    end
    if curM <= minM then
        return 1
    end
    local t = (1.0 - curM) / (1.0 - minM)
    if t < 0 then return 0 end
    if t > 1 then return 1 end
    return t
end

ConchBlessing.liveeye.onPickup = function(_, player, collectibleType, rng)
    ConchBlessing.printDebug("Live Eye item picked up!")
    player:AddCacheFlags(CacheFlag.CACHE_DAMAGE)
    player:EvaluateItems()
end

ConchBlessing.liveeye.onEvaluateCache = function(_, player, cacheFlag)
    if cacheFlag == CacheFlag.CACHE_DAMAGE then
        if player:HasCollectible(LIVE_EYE_ID) then
            local mult = ConchBlessing.liveeye.data.damageMultiplier
            
            if player:HasCollectible(CollectibleType.COLLECTIBLE_ROCK_BOTTOM) then
                mult = ConchBlessing.liveeye.data.maxDamageMultiplier
                ConchBlessing.printDebug("Live Eye + Rock Bottom synergy: damage multiplier locked at maximum!")
            else
                mult = math.max(
                    ConchBlessing.liveeye.data.minDamageMultiplier,
                    math.min(mult, ConchBlessing.liveeye.data.maxDamageMultiplier)
                )
            end
            
            -- Apply damage multiplier using stats system
            ConchBlessing.stats.damage.applyMultiplier(player, mult, nil, true)
            
            -- Show detailed multiplier display
            ConchBlessing.stats.multiplierDisplay:ShowDetailedMultipliers(
                player, "Damage", mult, mult, "Live Eye"
            )
            
            ConchBlessing.printDebug(string.format("Live Eye final mult=%.2f -> damage=%.2f", mult, player.Damage))
        end
    end
end

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

ConchBlessing.liveeye.onFireTear = function(_, tear)
    local parent = tear.Parent
    if parent and parent:ToPlayer() then
        local player = parent:ToPlayer()
        if player and player:HasCollectible(LIVE_EYE_ID) then
            local data = tear:GetData()
            data.conch_liveeye = { hit = false, ignoreRemoval = false }
            ConchBlessing.printDebug("Live Eye: tear tracking started (init)")
            
            local up, down
            if player:HasCollectible(CollectibleType.COLLECTIBLE_ROCK_BOTTOM) then
                up = 1.0
                down = 0.0
            else
                up = getAboveOneGlowRatio()
                down = getBelowOneGlowRatio()
            end
            
            if up > 0 then
                local r = 1.0 - 0.8 * up
                local g = 1.0 - 0.5 * up
                local b = 1.0
                local ro = 0.0
                local go = 0.5 * up
                local bo = 1.2 * up
                tear:SetColor(Color(r, g, b, 1.0, ro, go, bo), -1, 1, false, false)
                tear.Scale = tear.Scale * (1.0 + 0.15 * up)
            elseif down > 0 then
                local dim = 0.8 * down
                local r = 1.0 - dim
                local g = 1.0 - dim
                local b = 1.0 - dim
                tear:SetColor(Color(r, g, b, 1.0, 0, 0, 0), -1, 1, false, false)
                tear.Scale = tear.Scale * (1.0 - 0.1 * down)
            end
        end
    end
end

ConchBlessing.liveeye.onTearCollision = function(_, tear, collider, low)
    local parent = tear.Parent
    if not (parent and parent:ToPlayer()) then
        return nil
    end
    local player = parent:ToPlayer()
    if not (player and player:HasCollectible(LIVE_EYE_ID)) then
        return nil
    end

    local data = tear:GetData()
    if not data or not data.conch_liveeye or data.conch_liveeye.hit then
        return nil
    end

    if collider then
        local npc = collider:ToNPC()
        if npc and npc:IsVulnerableEnemy() and not npc:HasEntityFlags(EntityFlag.FLAG_FRIENDLY) then
            data.conch_liveeye.hit = true
            ConchBlessing.liveeye.handleHit()
            ConchBlessing.printDebug("Live Eye: player tear hit enemy! (HIT)")
            return nil
        end
    end
    if collider then
        local isFireEnt = (collider.Type == EntityType.ENTITY_FIREPLACE)
        local isPoopEnt = (collider.Type == EntityType.ENTITY_POOP)
        if not isPoopEnt then
            local ent = collider:ToNPC()
            if not ent then
                local name = tostring(collider:GetType()) .. ":" .. tostring(collider.Variant)
                if name:lower():find("poop") then
                    isPoopEnt = true
                end
            end
        end
        if isPoopEnt or isFireEnt then
            data.conch_liveeye.ignoreRemoval = true
            ConchBlessing.printDebug("Live Eye: tear hit poop/fire entity (IGNORED)")
        end
    end

    return nil
end

ConchBlessing.liveeye.onTearRemoved = function(_, entity)
    if entity.Type ~= EntityType.ENTITY_TEAR then
        return
    end
    local tear = entity:ToTear()
    if not tear then
        return
    end
    local parent = tear.Parent
    if not (parent and parent:ToPlayer()) then
        return
    end
    local player = parent:ToPlayer()
    if not (player and player:HasCollectible(LIVE_EYE_ID)) then
        return
    end

    local data = tear:GetData()
    if data and data.conch_liveeye and not data.conch_liveeye.hit then
        if data.conch_liveeye.ignoreRemoval then
            ConchBlessing.printDebug("Live Eye: tear removed after hitting poop/fire (IGNORED)")
            data.conch_liveeye.hit = true
            return
        end
        local room = Game():GetRoom()
        local grid = room and room:GetGridEntityFromPos(tear.Position) or nil
        if grid then
            local gtype = (grid.GetType and grid:GetType()) or nil
            local isTNTGrid = (GridEntityType and gtype == GridEntityType.GRID_TNT) or false
            local isPoopGrid = (GridEntityType and gtype == GridEntityType.GRID_POOP) or false
            local isFireGrid = (GridEntityType and gtype == GridEntityType.GRID_FIREPLACE) or false
            if isTNTGrid or isPoopGrid or isFireGrid then
                ConchBlessing.printDebug("Live Eye: tear removed near TNT/POOP/FIRE grid (IGNORED)")
                data.conch_liveeye.hit = true
                return
            end
        end
        ConchBlessing.liveeye.handleMiss()
        ConchBlessing.printDebug("Live Eye: tear removed without hitting (MISS)")
        data.conch_liveeye.hit = true
    end
end

ConchBlessing.liveeye.onGameStarted = function(_)
    ConchBlessing.liveeye.data.damageMultiplier = 1.0
    ConchBlessing.printDebug("Live Eye data initialized!")
    
    local player = Isaac.GetPlayer(0)
    if player and player:HasCollectible(LIVE_EYE_ID) then
        player:AddCacheFlags(CacheFlag.CACHE_DAMAGE)
        player:EvaluateItems()
    end
end

ConchBlessing.liveeye.onBeforeChange = function(upgradePos, pickup, itemData)
    return ConchBlessing.template.positive.onBeforeChange(upgradePos, pickup, ConchBlessing.liveeye.data)
end

ConchBlessing.liveeye.onAfterChange = function(upgradePos, pickup, itemData)
    ConchBlessing.template.positive.onAfterChange(upgradePos, pickup, ConchBlessing.liveeye.data)
end

ConchBlessing.liveeye.onUpdate = function(_)
    ConchBlessing.template.onUpdate(ConchBlessing.liveeye.data)
end