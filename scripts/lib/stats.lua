ConchBlessing.stats = {}

-- base stats
ConchBlessing.stats.BASE_STATS = {
    damage = 3.5,           -- base damage
    tears = 7,              -- base shots per second (MaxFireDelay)
    speed = 1.0,            -- base speed
    range = 6.5,            -- base range
    luck = 0,               -- base luck
    shotSpeed = 1.0         -- base shot speed
}

-- damage related functions
ConchBlessing.stats.damage = {}

-- apply damage multiplier (includes poison damage)
function ConchBlessing.stats.damage.applyMultiplier(player, multiplier, minDamage)
    if not player then return end
    
    local baseDamage = player.Damage
    local newDamage = baseDamage * multiplier
    
    -- apply minimum damage limit
    if minDamage then
        newDamage = math.max(minDamage, newDamage)
    end
    
    player.Damage = newDamage
    
    -- apply poison damage multiplier
    ConchBlessing.stats.damage.applyPoisonDamageMultiplier(player, multiplier)
    
    return newDamage
end

-- apply damage addition (includes poison damage)
function ConchBlessing.stats.damage.applyAddition(player, addition, minDamage)
    if not player then return end
    
    local baseDamage = player.Damage
    local newDamage = baseDamage + addition
    
    -- apply minimum damage limit
    if minDamage then
        newDamage = math.max(minDamage, newDamage)
    end
    
    player.Damage = newDamage
    
    -- apply poison damage addition
    ConchBlessing.stats.damage.applyPoisonDamageAddition(player, addition)
    
    return newDamage
end

-- apply poison damage multiplier
function ConchBlessing.stats.damage.applyPoisonDamageMultiplier(player, multiplier)
    if not player then return end
    
    -- check if poison damage API is supported
    if not ConchBlessing.stats.damage.supportsTearPoisonAPI(player) then
        return
    end
    
    local pdata = player:GetData()
    
    -- save base poison damage (only on first application)
    if not pdata.conch_stats_tpd_base then
        pdata.conch_stats_tpd_base = player:GetTearPoisonDamage()
    end
    
    -- reset to base value if multiplier is 1.0
    if multiplier == 1.0 then
        pdata.conch_stats_tpd_base = player:GetTearPoisonDamage()
    end
    
    local basePoisonDamage = pdata.conch_stats_tpd_base or 0
    local newPoisonDamage = basePoisonDamage * multiplier
    
    player:SetTearPoisonDamage(newPoisonDamage)
    pdata.conch_stats_tpd_lastMult = multiplier
    
    return newPoisonDamage
end

-- apply poison damage addition
function ConchBlessing.stats.damage.applyPoisonDamageAddition(player, addition)
    if not player then return end
    
    -- check if poison damage API is supported
    if not ConchBlessing.stats.damage.supportsTearPoisonAPI(player) then
        return
    end
    
    local pdata = player:GetData()
    
    -- save base poison damage (only on first application)
    if not pdata.conch_stats_tpd_base then
        pdata.conch_stats_tpd_base = player:GetTearPoisonDamage()
    end
    
    local basePoisonDamage = pdata.conch_stats_tpd_base or 0
    local newPoisonDamage = basePoisonDamage + addition
    
    player:SetTearPoisonDamage(newPoisonDamage)
    
    return newPoisonDamage
end

-- check if poison damage API is supported
function ConchBlessing.stats.damage.supportsTearPoisonAPI(player)
    return player and type(player.GetTearPoisonDamage) == "function" and type(player.SetTearPoisonDamage) == "function"
end

-- shot speed related functions
ConchBlessing.stats.tears = {}

-- calculate MaxFireDelay based on SPS (Shots Per Second)
function ConchBlessing.stats.tears.calculateMaxFireDelay(baseFireDelay, multiplier, minFireDelay)
    if not baseFireDelay or not multiplier then return baseFireDelay end
    
    -- calculate SPS: SPS = 30 / (MaxFireDelay + 1)
    local baseSPS = 30 / (baseFireDelay + 1)
    local targetSPS = baseSPS * multiplier
    local newMaxFireDelay = math.max(0, (30 / targetSPS) - 1)
    
    -- apply minimum fire delay limit
    if minFireDelay then
        newMaxFireDelay = math.max(minFireDelay, newMaxFireDelay)
    end
    
    return newMaxFireDelay
end

-- apply fire delay multiplier (based on SPS)
function ConchBlessing.stats.tears.applyMultiplier(player, multiplier, minFireDelay)
    if not player then return end
    
    local baseFireDelay = player.MaxFireDelay
    local newFireDelay = ConchBlessing.stats.tears.calculateMaxFireDelay(baseFireDelay, multiplier, minFireDelay)
    
    player.MaxFireDelay = newFireDelay
    
    return newFireDelay
end

-- apply fire delay addition (based on SPS)
function ConchBlessing.stats.tears.applyAddition(player, addition, minFireDelay)
    if not player then return end
    
    local baseFireDelay = player.MaxFireDelay
    local baseSPS = 30 / (baseFireDelay + 1)
    local targetSPS = baseSPS + addition
    local newFireDelay = math.max(0, (30 / targetSPS) - 1)
    
    -- apply minimum fire delay limit
    if minFireDelay then
        newFireDelay = math.max(minFireDelay, newFireDelay)
    end
    
    player.MaxFireDelay = newFireDelay

    return newFireDelay
end

-- unified stats apply functions
ConchBlessing.stats.unified = {}

-- apply multiplier to all stats
function ConchBlessing.stats.unified.applyMultiplierToAll(player, multiplier, minStats)
    if not player then return end
    
    minStats = minStats or ConchBlessing.stats.BASE_STATS
    
    -- damage
    ConchBlessing.stats.damage.applyMultiplier(player, multiplier, minStats.damage * 0.4)
    
    -- fire delay (based on SPS)
    ConchBlessing.stats.tears.applyMultiplier(player, multiplier, minStats.tears * 0.4)
    
    -- other stats
    player.MoveSpeed = math.max(minStats.speed * 0.4, player.MoveSpeed * multiplier)
    player.TearRange = math.max(minStats.range * 0.4, player.TearRange * multiplier)
    player.Luck = math.max(minStats.luck * 0.4, player.Luck * multiplier)
    player.ShotSpeed = math.max(minStats.shotSpeed * 0.4, player.ShotSpeed * multiplier)

    return true
end

-- apply addition to all stats
function ConchBlessing.stats.unified.applyAdditionToAll(player, addition, minStats)
    if not player then return end
    
    minStats = minStats or ConchBlessing.stats.BASE_STATS
    
    -- damage
    ConchBlessing.stats.damage.applyAddition(player, addition, minStats.damage * 0.4)
    
    -- fire delay (based on SPS)
    ConchBlessing.stats.tears.applyAddition(player, addition, minStats.tears * 0.4)
    
    -- other stats
    player.MoveSpeed = math.max(minStats.speed * 0.4, player.MoveSpeed + addition)
    player.TearRange = math.max(minStats.range * 0.4, player.TearRange + addition)
    player.Luck = math.max(minStats.luck * 0.4, player.Luck + addition)
    player.ShotSpeed = math.max(minStats.shotSpeed * 0.4, player.ShotSpeed + addition)
    return true
end

-- set stats cache flag and recalculate
function ConchBlessing.stats.unified.updateCache(player, cacheFlag)
    if not player then return end
    
    if cacheFlag then
        player:AddCacheFlags(cacheFlag)
    else
        player:AddCacheFlags(CacheFlag.CACHE_ALL)
    end
    
    player:EvaluateItems()
end

ConchBlessing.printDebug("Stats library loaded successfully!") 