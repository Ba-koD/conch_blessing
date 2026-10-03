ConchBlessing.liveeye = {}

ConchBlessing.liveeye.data = {
    damageMultiplier = 1.0,
    maxDamageMultiplier = 3.0,
    minDamageMultiplier = 0.75,
    hitMultiplierIncrease = 0.1,
    missMultiplierDecrease = 0.15,
    -- Chance that a miss leaves the multiplier alone: the base plus this much
    -- per point of luck, clamped to [0, 1] (Luck 10 forgives every miss).
    missForgiveBaseChance = 0.5,
    missForgiveLuckBonus = 0.05,
    -- Without a tear attack there is nothing to score as a hit or miss, so the
    -- multiplier is fixed here instead (Rock Bottom still fixes it at the maximum).
    nonTearDamageMultiplier = 1.5,
}

local LIVE_EYE_ID = Isaac.GetItemIdByName("Live Eye")

-- Runtime tallies read only by the dev test bench (scripts/dev/liveeye_probe.lua).
ConchBlessing.liveeye._counters = { misses = 0, forgiven = 0 }

---@param player table anything with a numeric Luck field
---@return number chance in [0, 1] that a miss does not lower the multiplier
local function getMissForgiveChance(player)
    local data = ConchBlessing.liveeye.data
    local luck = tonumber(player and player.Luck) or 0
    local chance = data.missForgiveBaseChance + data.missForgiveLuckBonus * luck
    return math.max(0, math.min(1, chance))
end

-- Weapon types that fire separate tears Live Eye can score as hits or misses.
-- Ludovico's single tear never leaves the room, so it can never miss and is
-- treated like every other non-tear attack.
local TEAR_WEAPONS = {
    [WeaponType.WEAPON_TEARS] = true,
    [WeaponType.WEAPON_MONSTROS_LUNGS] = true,
    [WeaponType.WEAPON_FETUS] = true,
}

--- true when the player attacks with tears only. Any other weapon type, even
--- alongside tears, counts as a non-tear attack.
local function usesTearAttacks(player)
    if type(player.HasWeaponType) ~= "function" then return true end
    local hasTears = false
    for weaponType = 1, (WeaponType.NUM_WEAPON_TYPES or 16) - 1 do
        if player:HasWeaponType(weaponType) then
            if not TEAR_WEAPONS[weaponType] then return false end
            hasTears = true
        end
    end
    return hasTears
end

--- The fixed multiplier, or nil while hits and misses drive it.
local function getFixedMultiplier(player)
    local data = ConchBlessing.liveeye.data
    if player:HasCollectible(CollectibleType.COLLECTIBLE_ROCK_BOTTOM) then
        return data.maxDamageMultiplier
    end
    if not usesTearAttacks(player) then
        return data.nonTearDamageMultiplier
    end
    return nil
end

function ConchBlessing.liveeye.getEffectiveMultiplier(player)
    local fixed = getFixedMultiplier(player)
    if fixed then return fixed end
    local data = ConchBlessing.liveeye.data
    return math.max(data.minDamageMultiplier, math.min(data.damageMultiplier, data.maxDamageMultiplier))
end

local function getAboveOneGlowRatio(curM)
    local maxM = ConchBlessing.liveeye.data.maxDamageMultiplier
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

local function getBelowOneGlowRatio(curM)
    local minM = ConchBlessing.liveeye.data.minDamageMultiplier
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
            local mult = ConchBlessing.liveeye.getEffectiveMultiplier(player)
            -- Runtime only: lets the test bench see the multiplier actually applied.
            player:GetData().__conchLiveEyeApplied = mult

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

-- player: the owner of the tear that hit.
ConchBlessing.liveeye.handleHit = function(player)
    player = player or Isaac.GetPlayer(0)
    local oldMultiplier = ConchBlessing.liveeye.data.damageMultiplier
    ConchBlessing.liveeye.data.damageMultiplier = math.min(
        ConchBlessing.liveeye.data.damageMultiplier + ConchBlessing.liveeye.data.hitMultiplierIncrease,
        ConchBlessing.liveeye.data.maxDamageMultiplier
    )

    if player then
        player:AddCacheFlags(CacheFlag.CACHE_DAMAGE)
        player:EvaluateItems()
    end
    
    ConchBlessing.printDebug(string.format("Live Eye: hit! multiplier %.2f -> %.2f", 
        oldMultiplier, ConchBlessing.liveeye.data.damageMultiplier))
end

-- player: the owner of the tear that missed; its luck sets the forgive chance.
ConchBlessing.liveeye.handleMiss = function(player)
    player = player or Isaac.GetPlayer(0)
    local counters = ConchBlessing.liveeye._counters
    counters.misses = counters.misses + 1
    local chance = getMissForgiveChance(player)
    if player and player:GetCollectibleRNG(LIVE_EYE_ID):RandomFloat() < chance then
        counters.forgiven = counters.forgiven + 1
        ConchBlessing.printDebug(string.format("Live Eye: miss forgiven (chance %.0f%%), multiplier stays %.2f",
            chance * 100, ConchBlessing.liveeye.data.damageMultiplier))
        return
    end

    local oldMultiplier = ConchBlessing.liveeye.data.damageMultiplier
    ConchBlessing.liveeye.data.damageMultiplier = math.max(
        ConchBlessing.liveeye.data.damageMultiplier - ConchBlessing.liveeye.data.missMultiplierDecrease,
        ConchBlessing.liveeye.data.minDamageMultiplier
    )

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
            -- A fixed multiplier ignores hits and misses, so its tears are not scored.
            if not getFixedMultiplier(player) then
                local data = tear:GetData()
                data.conch_liveeye = { hit = false, ignoreRemoval = false }
                ConchBlessing.printDebug("Live Eye: tear tracking started (init)")
            end

            local mult = ConchBlessing.liveeye.getEffectiveMultiplier(player)
            local up = getAboveOneGlowRatio(mult)
            local down = getBelowOneGlowRatio(mult)
            
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
            ConchBlessing.liveeye.handleHit(player)
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
        ConchBlessing.liveeye.handleMiss(player)
        ConchBlessing.printDebug("Live Eye: tear removed without hitting (MISS)")
        data.conch_liveeye.hit = true
    end
end

-- The base API has no weapon-changed callback, so a Live Eye holder's fixed
-- state (Rock Bottom, or a non-tear weapon such as Brimstone) is compared every
-- update and the damage cache is re-evaluated only when it changes.
ConchBlessing.liveeye.onPlayerUpdate = function(_, player)
    if not (player and player:HasCollectible(LIVE_EYE_ID)) then return end
    local state = getFixedMultiplier(player) or 0
    local pdata = player:GetData()
    if pdata.__conchLiveEyeFixedState == state then return end
    local first = pdata.__conchLiveEyeFixedState == nil
    pdata.__conchLiveEyeFixedState = state
    if not first then
        player:AddCacheFlags(CacheFlag.CACHE_DAMAGE)
        player:EvaluateItems()
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

-- Test hooks for scripts/dev/rng_probe.lua. Pure helpers, no gameplay use.
ConchBlessing.liveeye._test = {
    getMissForgiveChance = getMissForgiveChance,
    getFixedMultiplier = getFixedMultiplier,
    usesTearAttacks = usesTearAttacks,
}
