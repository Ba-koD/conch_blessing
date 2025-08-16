-- Stats Management Library (스탯 관리 라이브러리)
-- 데미지, 연사속도, 포이즌 데미지 등을 전역으로 관리

ConchBlessing.stats = {}

-- 기본 아이작 스탯 값들 (최소 제한을 위한 기준값)
ConchBlessing.stats.BASE_STATS = {
    damage = 3.5,           -- 기본 데미지
    tears = 7,              -- 기본 연사속도 (MaxFireDelay)
    speed = 1.0,            -- 기본 이동속도
    range = 6.5,            -- 기본 사거리
    luck = 0,               -- 기본 행운
    shotSpeed = 1.0         -- 기본 탄속
}

-- 데미지 관련 함수들
ConchBlessing.stats.damage = {}

-- 데미지 배수 적용 (포이즌 데미지 포함)
function ConchBlessing.stats.damage.applyMultiplier(player, multiplier, minDamage)
    if not player then return end
    
    local baseDamage = player.Damage
    local newDamage = baseDamage * multiplier
    
    -- 최소 데미지 제한 적용
    if minDamage then
        newDamage = math.max(minDamage, newDamage)
    end
    
    player.Damage = newDamage
    
    -- 포이즌 데미지도 동시에 처리
    ConchBlessing.stats.damage.applyPoisonDamageMultiplier(player, multiplier)
    
    ConchBlessing.printDebug(string.format("Stats: Damage multiplier %.2fx applied (%.2f -> %.2f)", 
        multiplier, baseDamage, newDamage))
    
    return newDamage
end

-- 데미지 덧셈 적용 (포이즌 데미지 포함)
function ConchBlessing.stats.damage.applyAddition(player, addition, minDamage)
    if not player then return end
    
    local baseDamage = player.Damage
    local newDamage = baseDamage + addition
    
    -- 최소 데미지 제한 적용
    if minDamage then
        newDamage = math.max(minDamage, newDamage)
    end
    
    player.Damage = newDamage
    
    -- 포이즌 데미지도 동시에 처리
    ConchBlessing.stats.damage.applyPoisonDamageAddition(player, addition)
    
    ConchBlessing.printDebug(string.format("Stats: Damage addition %.2f applied (%.2f -> %.2f)", 
        addition, baseDamage, newDamage))
    
    return newDamage
end

-- 포이즌 데미지 배수 적용
function ConchBlessing.stats.damage.applyPoisonDamageMultiplier(player, multiplier)
    if not player then return end
    
    -- 포이즌 데미지 API 지원 확인
    if not ConchBlessing.stats.damage.supportsTearPoisonAPI(player) then
        return
    end
    
    local pdata = player:GetData()
    
    -- 기본 포이즌 데미지 저장 (첫 번째 적용시에만)
    if not pdata.conch_stats_tpd_base then
        pdata.conch_stats_tpd_base = player:GetTearPoisonDamage()
    end
    
    -- 배수가 1.0이면 기본값으로 리셋
    if multiplier == 1.0 then
        pdata.conch_stats_tpd_base = player:GetTearPoisonDamage()
    end
    
    local basePoisonDamage = pdata.conch_stats_tpd_base or 0
    local newPoisonDamage = basePoisonDamage * multiplier
    
    player:SetTearPoisonDamage(newPoisonDamage)
    pdata.conch_stats_tpd_lastMult = multiplier
    
    ConchBlessing.printDebug(string.format("Stats: Poison damage multiplier %.2fx applied (%.2f -> %.2f)", 
        multiplier, basePoisonDamage, newPoisonDamage))
    
    return newPoisonDamage
end

-- 포이즌 데미지 덧셈 적용
function ConchBlessing.stats.damage.applyPoisonDamageAddition(player, addition)
    if not player then return end
    
    -- 포이즌 데미지 API 지원 확인
    if not ConchBlessing.stats.damage.supportsTearPoisonAPI(player) then
        return
    end
    
    local pdata = player:GetData()
    
    -- 기본 포이즌 데미지 저장 (첫 번째 적용시에만)
    if not pdata.conch_stats_tpd_base then
        pdata.conch_stats_tpd_base = player:GetTearPoisonDamage()
    end
    
    local basePoisonDamage = pdata.conch_stats_tpd_base or 0
    local newPoisonDamage = basePoisonDamage + addition
    
    player:SetTearPoisonDamage(newPoisonDamage)
    
    ConchBlessing.printDebug(string.format("Stats: Poison damage addition %.2f applied (%.2f -> %.2f)", 
        addition, basePoisonDamage, newPoisonDamage))
    
    return newPoisonDamage
end

-- 포이즌 데미지 API 지원 확인
function ConchBlessing.stats.damage.supportsTearPoisonAPI(player)
    return player and type(player.GetTearPoisonDamage) == "function" and type(player.SetTearPoisonDamage) == "function"
end

-- 연사속도 관련 함수들
ConchBlessing.stats.tears = {}

-- SPS (Shots Per Second) 기반으로 MaxFireDelay 계산
function ConchBlessing.stats.tears.calculateMaxFireDelay(baseFireDelay, multiplier, minFireDelay)
    if not baseFireDelay or not multiplier then return baseFireDelay end
    
    -- SPS 계산: SPS = 30 / (MaxFireDelay + 1)
    local baseSPS = 30 / (baseFireDelay + 1)
    local targetSPS = baseSPS * multiplier
    local newMaxFireDelay = math.max(0, (30 / targetSPS) - 1)
    
    -- 최소 연사속도 제한 적용
    if minFireDelay then
        newMaxFireDelay = math.max(minFireDelay, newMaxFireDelay)
    end
    
    ConchBlessing.printDebug(string.format("Stats: FireDelay SPS calculation (%.2f -> %.2f SPS, %.2f -> %.2f)", 
        baseSPS, targetSPS, baseFireDelay, newMaxFireDelay))
    
    return newMaxFireDelay
end

-- 연사속도 배수 적용 (SPS 기반)
function ConchBlessing.stats.tears.applyMultiplier(player, multiplier, minFireDelay)
    if not player then return end
    
    local baseFireDelay = player.MaxFireDelay
    local newFireDelay = ConchBlessing.stats.tears.calculateMaxFireDelay(baseFireDelay, multiplier, minFireDelay)
    
    player.MaxFireDelay = newFireDelay
    
    ConchBlessing.printDebug(string.format("Stats: FireDelay multiplier %.2fx applied (%.2f -> %.2f)", 
        multiplier, baseFireDelay, newFireDelay))
    
    return newFireDelay
end

-- 연사속도 덧셈 적용 (SPS 기반)
function ConchBlessing.stats.tears.applyAddition(player, addition, minFireDelay)
    if not player then return end
    
    local baseFireDelay = player.MaxFireDelay
    local baseSPS = 30 / (baseFireDelay + 1)
    local targetSPS = baseSPS + addition
    local newFireDelay = math.max(0, (30 / targetSPS) - 1)
    
    -- 최소 연사속도 제한 적용
    if minFireDelay then
        newFireDelay = math.max(minFireDelay, newFireDelay)
    end
    
    player.MaxFireDelay = newFireDelay
    
    ConchBlessing.printDebug(string.format("Stats: FireDelay addition %.2f SPS applied (%.2f -> %.2f SPS, %.2f -> %.2f)", 
        addition, baseSPS, targetSPS, baseFireDelay, newFireDelay))
    
    return newFireDelay
end

-- 통합 스탯 적용 함수들
ConchBlessing.stats.unified = {}

-- 모든 스탯에 배수 적용
function ConchBlessing.stats.unified.applyMultiplierToAll(player, multiplier, minStats)
    if not player then return end
    
    minStats = minStats or ConchBlessing.stats.BASE_STATS
    
    -- 데미지
    ConchBlessing.stats.damage.applyMultiplier(player, multiplier, minStats.damage * 0.4)
    
    -- 연사속도 (SPS 기반)
    ConchBlessing.stats.tears.applyMultiplier(player, multiplier, minStats.tears * 0.4)
    
    -- 기타 스탯들
    player.MoveSpeed = math.max(minStats.speed * 0.4, player.MoveSpeed * multiplier)
    player.TearRange = math.max(minStats.range * 0.4, player.TearRange * multiplier)
    player.Luck = math.max(minStats.luck * 0.4, player.Luck * multiplier)
    player.ShotSpeed = math.max(minStats.shotSpeed * 0.4, player.ShotSpeed * multiplier)
    
    ConchBlessing.printDebug(string.format("Stats: All stats multiplier %.2fx applied", multiplier))
    
    return true
end

-- 모든 스탯에 덧셈 적용
function ConchBlessing.stats.unified.applyAdditionToAll(player, addition, minStats)
    if not player then return end
    
    minStats = minStats or ConchBlessing.stats.BASE_STATS
    
    -- 데미지
    ConchBlessing.stats.damage.applyAddition(player, addition, minStats.damage * 0.4)
    
    -- 연사속도 (SPS 기반)
    ConchBlessing.stats.tears.applyAddition(player, addition, minStats.tears * 0.4)
    
    -- 기타 스탯들
    player.MoveSpeed = math.max(minStats.speed * 0.4, player.MoveSpeed + addition)
    player.TearRange = math.max(minStats.range * 0.4, player.TearRange + addition)
    player.Luck = math.max(minStats.luck * 0.4, player.Luck + addition)
    player.ShotSpeed = math.max(minStats.shotSpeed * 0.4, player.ShotSpeed + addition)
    
    ConchBlessing.printDebug(string.format("Stats: All stats addition %.2f applied", addition))
    
    return true
end

-- 스탯 캐시 플래그 설정 및 재계산
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