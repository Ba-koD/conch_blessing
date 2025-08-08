ConchBlessing.liveeye = {}

-- Live Eye effect variables
ConchBlessing.liveeye.data = {
    damageMultiplier = 1.0,
    maxDamageMultiplier = 3.0,
    minDamageMultiplier = 0.5,
    hitMultiplierIncrease = 0.1,
    missMultiplierDecrease = 0.15,
}

local LIVE_EYE_ID = Isaac.GetItemIdByName("Live Eye")

-- Ratio only for values above 1.0 (no glow at <= 1.0), normalized to [0..1] over [1.0..max]
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

-- Ratio only for values below 1.0 (no glow at >= 1.0), normalized to [0..1] over [min..1.0]
local function getBelowOneGlowRatio()
    local minM = ConchBlessing.liveeye.data.minDamageMultiplier
    local curM = ConchBlessing.liveeye.data.damageMultiplier
    if curM >= 1.0 then
        return 0
    end
    if 1.0 <= minM then
        return 0
    end
    local t = (1.0 - curM) / (1.0 - minM)
    if t < 0 then return 0 end
    if t > 1 then return 1 end
    return t
end

-- on pickup
ConchBlessing.liveeye.onPickup = function(_, player, collectibleType, rng)
    ConchBlessing.printDebug("Live Eye item picked up!")
    -- add damage cache flag
    player:AddCacheFlags(CacheFlag.CACHE_DAMAGE)
    player:EvaluateItems()
end

-- calculate damage multiplier
ConchBlessing.liveeye.onEvaluateCache = function(_, player, cacheFlag)
    if cacheFlag == CacheFlag.CACHE_DAMAGE then
        if player:HasCollectible(LIVE_EYE_ID) then
            -- Engine recalculates base each EvaluateCache; multiply once by current (clamped) multiplier
            local target = math.max(
                ConchBlessing.liveeye.data.minDamageMultiplier,
                math.min(ConchBlessing.liveeye.data.damageMultiplier, ConchBlessing.liveeye.data.maxDamageMultiplier)
            )
            player.Damage = player.Damage * target
            ConchBlessing.printDebug(string.format("Live Eye applied multiplier: %.2f -> damage=%.2f", target, player.Damage))
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
ConchBlessing.liveeye.onFireTear = function(_, tear)
    local parent = tear.Parent
    if parent and parent:ToPlayer() then
        local player = parent:ToPlayer()
        if player and player:HasCollectible(LIVE_EYE_ID) then
            local data = tear:GetData()
            data.conch_liveeye = { hit = false, ignoreRemoval = false }
            ConchBlessing.printDebug("Live Eye: tear tracking started (init)")

            -- Tint tears more blue as multiplier approaches max
            local up = getAboveOneGlowRatio()
            local down = getBelowOneGlowRatio()
            if up > 0 then
                -- Strong blue glow (Dead Eye 스타일의 강한 발광감을 파란색으로)
                local r = 1.0 - 0.8 * up
                local g = 1.0 - 0.5 * up
                local b = 1.0
                -- 강한 파랑/청록 계열의 additive 오프셋
                local ro = 0.0
                local go = 0.5 * up
                local bo = 1.2 * up
                tear:SetColor(Color(r, g, b, 1.0, ro, go, bo), -1, 1, false, false)
                -- 살짝 크기도 키워 존재감 강화
                tear.Scale = tear.Scale * (1.0 + 0.15 * up)
            elseif down > 0 then
                -- 강한 검은 광휘 느낌: 채널을 크게 낮춰 어둡게
                local dim = 0.8 * down
                local r = 1.0 - dim
                local g = 1.0 - dim
                local b = 1.0 - dim
                tear:SetColor(Color(r, g, b, 1.0, 0, 0, 0), -1, 1, false, false)
                -- 약간 작아지게 해서 위축된 느낌
                tear.Scale = tear.Scale * (1.0 - 0.1 * down)
            end
        end
    end
end

-- track tear collision with enemies (MC_PRE_TEAR_COLLISION)
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
        -- Non-enemy collisions should not count as MISS immediately.
        -- If collided with poop/fire entity specifically, avoid MISS on removal.
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

-- handle tear removal (MC_POST_ENTITY_REMOVE)
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
        -- Check grid at position: ignore MISS if TNT/POOP/FIREPLACE grid
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

-- initialize data when game starts
ConchBlessing.liveeye.onGameStarted = function(_)
    ConchBlessing.liveeye.data.damageMultiplier = 1.0
    ConchBlessing.printDebug("Live Eye data initialized!")
    
    -- apply item effect when game starts
    local player = Isaac.GetPlayer(0)
    if player and player:HasCollectible(LIVE_EYE_ID) then
        player:AddCacheFlags(CacheFlag.CACHE_DAMAGE)
        player:EvaluateItems()
    end
end

-- optional custom upgrade handlers (called by upgrade system)
ConchBlessing.liveeye.onBeforeChange = function(upgradePos, pickup, itemData)
    -- strong, long and noticeable pre-upgrade effect
    -- screen shake cue
    Game():ShakeScreen(10)

    -- central halo lasting longer
    local center = Isaac.Spawn(EntityType.ENTITY_EFFECT, EffectVariant.HALO, 0, upgradePos, Vector.Zero, nil):ToEffect()
    if center then
        center.Timeout = 60
        center.DepthOffset = -20
        center.SpriteScale = Vector(2.0, 2.0)
        center:SetColor(Color(0.8, 0.9, 1.0, 0.9, 0.0, 0.25, 0.6), -1, 1, false, false)
    end

    -- ring of halos around the pedestal
    local ringRadius = 48
    for a = 0, 315, 45 do
        local rad = a * (math.pi / 180)
        local pos = upgradePos + Vector(math.cos(rad), math.sin(rad)) * ringRadius
        local e = Isaac.Spawn(EntityType.ENTITY_EFFECT, EffectVariant.HALO, 0, pos, Vector.Zero, nil):ToEffect()
        if e then
            e.Timeout = 40
            e.DepthOffset = -15
            e.SpriteScale = Vector(1.2, 1.2)
            e:SetColor(Color(0.7, 0.85, 1.0, 0.7, 0.0, 0.2, 0.5), -1, 1, false, false)
        end
    end

    -- descending light strike (single) to distinguish BEFORE from AFTER branching
    Isaac.Spawn(EntityType.ENTITY_EFFECT, EffectVariant.CRACK_THE_SKY, 0, upgradePos, Vector.Zero, nil)
end

ConchBlessing.liveeye.onAfterChange = function(upgradePos, pickup, itemData)
    -- stronger Holy Light burst at the pedestal
    for i = 1, 4 do
        local offset = Vector(math.random(-25, 25), math.random(-25, 25))
        Isaac.Spawn(EntityType.ENTITY_EFFECT, EffectVariant.CRACK_THE_SKY, 0, upgradePos + offset, Vector.Zero, nil)
    end
end

-- subtle blue halo when close to max multiplier
ConchBlessing.liveeye.onUpdate = function(_)
    -- No player aura; halo is applied to tears on spawn via additive color offset
end