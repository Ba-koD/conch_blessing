ConchBlessing.injectablsteroids = {}

local INJECTABLE_STEROIDS_ID = Isaac.GetItemIdByName("Injectable Steroids")
ConchBlessing.printDebug("Injectable Steroids ID: " .. tostring(INJECTABLE_STEROIDS_ID))

-- data table for upgrade system
ConchBlessing.injectablsteroids.data = {
    minMultiplier = 0.6,
    maxMultiplier = 2.0
}
ConchBlessing.injectablsteroids.storedMultipliers = {}

-- 디버그: 함수 정의 확인
ConchBlessing.printDebug("Defining onUseItem function for Injectable Steroids")

ConchBlessing.injectablsteroids.onUseItem = function(player, collectibleID, useFlags, activeSlot, customVarData)
    ConchBlessing.printDebug("onUseItem called! player: " .. tostring(player) .. ", collectibleID: " .. tostring(collectibleID) .. ", INJECTABLE_STEROIDS_ID: " .. tostring(INJECTABLE_STEROIDS_ID))
    
    -- collectibleID 체크
    if collectibleID ~= INJECTABLE_STEROIDS_ID then 
        ConchBlessing.printDebug("collectibleID mismatch, returning")
        return 
    end
    
    -- player 객체 검증 강화
    if not player or not player.Position or not player.GetPlayerType then
        ConchBlessing.printDebug("Invalid player object, trying to get player from Isaac.GetPlayer(0)")
        player = Isaac.GetPlayer(0)
        if not player then
            ConchBlessing.printDebug("Failed to get player from Isaac.GetPlayer(0), returning")
            return
        end
        ConchBlessing.printDebug("Successfully got player from Isaac.GetPlayer(0)")
    end
    
    ConchBlessing.printDebug("Injectable Steroids use effect starting...")
    
    -- Razor Blade와 같은 모션 효과
    -- 1. 아이템을 들고 있는 모션
    player:AnimateCollectible(INJECTABLE_STEROIDS_ID, "Pickup", "PlayerPickupSparkle")
    
    -- 2. 잠시 대기 (들고 있는 시간)
    local waitFrames = 15 -- 15프레임 대기
    
    -- 3. 아이템을 놓는 모션과 효과
    local function finishUse()
        ConchBlessing.printDebug("finishUse called!")
        
        -- 새로운 배수를 추가할 인덱스 (기존 개수 + 1)
        local playerID = player:GetPlayerType()
        if not ConchBlessing.injectablsteroids.storedMultipliers[playerID] then
            ConchBlessing.injectablsteroids.storedMultipliers[playerID] = {}
        end
        
        -- 이미 사용된 상태인지 확인 (무한 루프 방지)
        if ConchBlessing.injectablsteroids._isUsing then
            ConchBlessing.printDebug("Injectable Steroids: Already in use, skipping...")
            return
        end
        
        ConchBlessing.injectablsteroids._isUsing = true
        
        local newIndex = #ConchBlessing.injectablsteroids.storedMultipliers[playerID] + 1
        
        local newMultipliers = {
            speed = math.random() * (ConchBlessing.injectablsteroids.data.maxMultiplier - ConchBlessing.injectablsteroids.data.minMultiplier) + ConchBlessing.injectablsteroids.data.minMultiplier,
            tears = math.random() * (ConchBlessing.injectablsteroids.data.maxMultiplier - ConchBlessing.injectablsteroids.data.minMultiplier) + ConchBlessing.injectablsteroids.data.minMultiplier,
            damage = math.random() * (ConchBlessing.injectablsteroids.data.maxMultiplier - ConchBlessing.injectablsteroids.data.minMultiplier) + ConchBlessing.injectablsteroids.data.minMultiplier,
            range = math.random() * (ConchBlessing.injectablsteroids.data.maxMultiplier - ConchBlessing.injectablsteroids.data.minMultiplier) + ConchBlessing.injectablsteroids.data.minMultiplier,
            shotSpeed = math.random() * (ConchBlessing.injectablsteroids.data.maxMultiplier - ConchBlessing.injectablsteroids.data.minMultiplier) + ConchBlessing.injectablsteroids.data.minMultiplier,
            luck = math.random() * (ConchBlessing.injectablsteroids.data.maxMultiplier - ConchBlessing.injectablsteroids.data.minMultiplier) + ConchBlessing.injectablsteroids.data.minMultiplier
        }
        
        table.insert(ConchBlessing.injectablsteroids.storedMultipliers[playerID], newMultipliers)
        
        -- 디버그 출력
        ConchBlessing.printDebug(string.format("Injectable Steroids #%d used: Speed=%.2fx Tears=%.2fx Damage=%.2fx Range=%.2fx ShotSpeed=%.2fx Luck=%.2fx", 
            newIndex, newMultipliers.speed, newMultipliers.tears, newMultipliers.damage, newMultipliers.range, newMultipliers.shotSpeed, newMultipliers.luck))
        
        -- Razor Blade와 같은 피격음 (hurt grunt 소리)
        SFXManager():Play(SoundEffect.SOUND_ISAAC_HURT_GRUNT, 1.0, 0, false, 1.0, 0)
        
        -- 추가적인 hurt 소리들 (더 다양한 피격음)
        SFXManager():Play(SoundEffect.SOUND_ISAAC_HURT_GRUNT, 0.8, 0, false, 0.8, 0)
        SFXManager():Play(SoundEffect.SOUND_ISAAC_HURT_GRUNT, 0.6, 0, false, 0.6, 0)
        
        -- 주사 효과 (면도기처럼 피격하는 느낌)
        local injectionEffect = Isaac.Spawn(EntityType.ENTITY_EFFECT, 0, 0, player.Position, Vector.Zero, player)
        if injectionEffect then
            injectionEffect:SetTimeout(45)
        end
        
        -- 스테로이드 러시 효과
        local steroidRush = Isaac.Spawn(EntityType.ENTITY_EFFECT, 1, 0, player.Position, Vector.Zero, player)
        if steroidRush then
            steroidRush:SetTimeout(60)
        end
        
        -- 플레이어 피부색을 점점 노랗게 변경 (스테로이드 효과)
        if not ConchBlessing.injectablsteroids._yellowTintFrames then
            ConchBlessing.injectablsteroids._yellowTintFrames = 0
        end
        if not ConchBlessing.injectablsteroids._yellowIntensity then
            ConchBlessing.injectablsteroids._yellowIntensity = 0
        end
        
        -- 노란색 강도 누적 (사용할 때마다 점점 더 노랗게)
        ConchBlessing.injectablsteroids._yellowIntensity = ConchBlessing.injectablsteroids._yellowIntensity + 0.3
        ConchBlessing.injectablsteroids._yellowTintFrames = 180 -- 3초간 지속
        
        -- 아이템을 놓는 모션
        player:AnimateCollectible(INJECTABLE_STEROIDS_ID, "Drop", "PlayerPickupSparkle")
        
        -- 사용 상태 해제
        ConchBlessing.injectablsteroids._isUsing = false
        
        ConchBlessing.printDebug("Injectable Steroids use effect completed!")
    end
    
    -- 잠시 대기 후 효과 실행
    -- 15프레임 후 효과 실행 (POST_UPDATE 콜백 사용)
    local updateCallback = function()
        if waitFrames > 0 then
            waitFrames = waitFrames - 1
            ConchBlessing.printDebug("Injectable Steroids: Waiting... " .. waitFrames .. " frames remaining")
        else
            ConchBlessing.printDebug("Injectable Steroids: Delay finished, executing effects...")
            finishUse()
            -- 콜백 제거
            ConchBlessing:RemoveCallback(ModCallbacks.MC_POST_UPDATE, updateCallback)
        end
    end
    
    ConchBlessing:AddCallback(ModCallbacks.MC_POST_UPDATE, updateCallback)
    
    ConchBlessing.printDebug("onUseItem returning: Discharge=false, Remove=false, ShowAnim=true")
    return { Discharge = false, Remove = false, ShowAnim = true }
end

-- 디버그: 함수 정의 완료 확인
ConchBlessing.printDebug("onUseItem function defined successfully")
ConchBlessing.printDebug("Function type: " .. type(ConchBlessing.injectablsteroids.onUseItem))

ConchBlessing.injectablsteroids.onEvaluateCache = function(_, player, cacheFlag)
    if not player:HasCollectible(INJECTABLE_STEROIDS_ID) then return end
    
    local playerID = player:GetPlayerType()
    local itemNum = player:GetCollectibleNum(INJECTABLE_STEROIDS_ID)
    
    if itemNum <= 0 then return end
    
    -- storedMultipliers가 없으면 초기화
    if not ConchBlessing.injectablsteroids.storedMultipliers then
        ConchBlessing.injectablsteroids.storedMultipliers = {}
    end
    
    if not ConchBlessing.injectablsteroids.storedMultipliers[playerID] then
        ConchBlessing.injectablsteroids.storedMultipliers[playerID] = {}
    end
    
    -- 현재 저장된 배수 개수와 실제 아이템 개수 비교
    local storedCount = #ConchBlessing.injectablsteroids.storedMultipliers[playerID]
    if itemNum > storedCount then
        -- 새로운 아이템이 추가됨 - 새로운 배수 생성
        for i = storedCount + 1, itemNum do
            -- math.random() 사용하여 간단하게 랜덤 배수 생성
            local newMultipliers = {
                speed = math.random() * (ConchBlessing.injectablsteroids.data.maxMultiplier - ConchBlessing.injectablsteroids.data.minMultiplier) + ConchBlessing.injectablsteroids.data.minMultiplier,
                tears = math.random() * (ConchBlessing.injectablsteroids.data.maxMultiplier - ConchBlessing.injectablsteroids.data.minMultiplier) + ConchBlessing.injectablsteroids.data.minMultiplier,
                damage = math.random() * (ConchBlessing.injectablsteroids.data.maxMultiplier - ConchBlessing.injectablsteroids.data.minMultiplier) + ConchBlessing.injectablsteroids.data.minMultiplier,
                range = math.random() * (ConchBlessing.injectablsteroids.data.maxMultiplier - ConchBlessing.injectablsteroids.data.minMultiplier) + ConchBlessing.injectablsteroids.data.minMultiplier,
                shotSpeed = math.random() * (ConchBlessing.injectablsteroids.data.maxMultiplier - ConchBlessing.injectablsteroids.data.minMultiplier) + ConchBlessing.injectablsteroids.data.minMultiplier,
                luck = math.random() * (ConchBlessing.injectablsteroids.data.maxMultiplier - ConchBlessing.injectablsteroids.data.minMultiplier) + ConchBlessing.injectablsteroids.data.minMultiplier
            }
            table.insert(ConchBlessing.injectablsteroids.storedMultipliers[playerID], newMultipliers)
            
            -- 각 아이템의 개별 배수 출력 (한 번만)
            ConchBlessing.printDebug(string.format("Injectable Steroids #%d: Speed=%.2fx Tears=%.2fx Damage=%.2fx Range=%.2fx ShotSpeed=%.2fx Luck=%.2fx", 
                i, newMultipliers.speed, newMultipliers.tears, newMultipliers.damage, newMultipliers.range, newMultipliers.shotSpeed, newMultipliers.luck))
        end
        ConchBlessing.printDebug("Injectable Steroids: Added " .. (itemNum - storedCount) .. " new multipliers")
    end
    
    -- 디버그 출력 최소화 (초기화 시에만)
    if cacheFlag == CacheFlag.CACHE_DAMAGE and itemNum ~= ConchBlessing.injectablsteroids._lastDebugItemNum then
        ConchBlessing.printDebug("Injectable Steroids: storedMultipliers count: " .. #ConchBlessing.injectablsteroids.storedMultipliers[playerID])
        ConchBlessing.injectablsteroids._lastDebugItemNum = itemNum
    end
    
    local totalSpeed = 1.0
    local totalTears = 1.0
    local totalDamage = 1.0
    local totalRange = 1.0
    local totalShotSpeed = 1.0
    local totalLuck = 1.0
    
    -- 저장된 배수들을 사용하여 누적 계산
    local storedMultipliers = ConchBlessing.injectablsteroids.storedMultipliers[playerID]
    for i = 1, math.min(itemNum, #storedMultipliers) do
        local multipliers = storedMultipliers[i]
        totalSpeed = totalSpeed * multipliers.speed
        totalTears = totalTears * multipliers.tears
        totalDamage = totalDamage * multipliers.damage
        totalRange = totalRange * multipliers.range
        totalShotSpeed = totalShotSpeed * multipliers.shotSpeed
        totalLuck = totalLuck * multipliers.luck
    end
    
    totalSpeed = math.max(ConchBlessing.injectablsteroids.data.minMultiplier, totalSpeed)
    totalTears = math.max(ConchBlessing.injectablsteroids.data.minMultiplier, totalTears)
    totalDamage = math.max(ConchBlessing.injectablsteroids.data.minMultiplier, totalDamage)
    totalRange = math.max(ConchBlessing.injectablsteroids.data.minMultiplier, totalRange)
    totalShotSpeed = math.max(ConchBlessing.injectablsteroids.data.minMultiplier, totalShotSpeed)
    totalLuck = math.max(ConchBlessing.injectablsteroids.data.minMultiplier, totalLuck)
    
    -- 디버그 출력은 CACHE_DAMAGE에서만 한 번 (아이템 개수 변경 시에만)
    if cacheFlag == CacheFlag.CACHE_DAMAGE and itemNum ~= ConchBlessing.injectablsteroids._lastFinalDebugItemNum then
        ConchBlessing.printDebug(string.format("Injectable Steroids Final (x%d): Speed=%.2fx Tears=%.2fx Damage=%.2fx Range=%.2fx ShotSpeed=%.2fx Luck=%.2fx", 
            itemNum, totalSpeed, totalTears, totalDamage, totalRange, totalShotSpeed, totalLuck))
        ConchBlessing.injectablsteroids._lastFinalDebugItemNum = itemNum
    end
    
    -- 실제로 스탯 적용 (stats.lua 함수 사용)
    if cacheFlag == CacheFlag.CACHE_FIREDELAY then
        ConchBlessing.stats.tears.applyMultiplier(player, totalTears, ConchBlessing.injectablsteroids.data.minMultiplier)
        ConchBlessing.printDebug("Injectable Steroids: Applied tears multiplier: " .. totalTears)
    end
    
    if cacheFlag == CacheFlag.CACHE_DAMAGE then
        ConchBlessing.stats.damage.applyMultiplier(player, totalDamage, ConchBlessing.injectablsteroids.data.minMultiplier)
        ConchBlessing.printDebug("Injectable Steroids: Applied damage multiplier: " .. totalDamage)
    end
    
    if cacheFlag == CacheFlag.CACHE_SPEED then
        player.MoveSpeed = player.MoveSpeed * totalSpeed
        ConchBlessing.printDebug("Injectable Steroids: Applied speed multiplier: " .. totalSpeed .. " -> " .. player.MoveSpeed)
    end
    
    if cacheFlag == CacheFlag.CACHE_RANGE then
        player.TearRange = player.TearRange * totalRange
        ConchBlessing.printDebug("Injectable Steroids: Applied range multiplier: " .. totalRange .. " -> " .. player.TearRange)
    end
    
    if cacheFlag == CacheFlag.CACHE_LUCK and player.Luck > 0 then
        player.Luck = player.Luck * totalLuck
        ConchBlessing.printDebug("Injectable Steroids: Applied luck multiplier: " .. totalLuck .. " -> " .. player.Luck)
    end
    
    if cacheFlag == CacheFlag.CACHE_SHOTSPEED then
        player.ShotSpeed = player.ShotSpeed * totalShotSpeed
        ConchBlessing.printDebug("Injectable Steroids: Applied shotSpeed multiplier: " .. totalShotSpeed .. " -> " .. player.ShotSpeed)
    end
end

-- initialize data when game started
ConchBlessing.injectablsteroids.onGameStarted = function(_)
    ConchBlessing.injectablsteroids.storedMultipliers = {}
    ConchBlessing.injectablsteroids._isUsing = false
    ConchBlessing.printDebug("Injectable Steroids: onGameStarted called!")
    ConchBlessing.printDebug("Injectable Steroids data initialized!")
    ConchBlessing.printDebug("storedMultipliers table created!")
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
    
    -- 스테로이드 사용 후 피부색을 점점 노랗게 변경
    if ConchBlessing.injectablsteroids._yellowTintFrames and ConchBlessing.injectablsteroids._yellowTintFrames > 0 then
        local player = Isaac.GetPlayer(0) -- 첫 번째 플레이어
        if player then
            -- 누적된 노란색 강도 사용 (사용할 때마다 점점 더 노랗게)
            local yellowIntensity = math.min(ConchBlessing.injectablsteroids._yellowIntensity or 0, 1.0)
            local currentColor = player:GetColor()
            
            -- 기존 색상에 노란색을 점진적으로 추가
            local newColor = Color(
                currentColor.R + (0.3 * yellowIntensity), -- 빨강 증가
                currentColor.G + (0.2 * yellowIntensity), -- 초록 증가  
                currentColor.B - (0.1 * yellowIntensity), -- 파랑 감소
                currentColor.A, -- 알파값 유지
                currentColor.RO + (0.3 * yellowIntensity), -- 빨강 오프셋
                currentColor.GO + (0.2 * yellowIntensity), -- 초록 오프셋
                currentColor.BO - (0.1 * yellowIntensity)  -- 파랑 오프셋
            )
            
            player:SetColor(newColor, 0, 0, false, false)
            
            -- 프레임 감소
            ConchBlessing.injectablsteroids._yellowTintFrames = ConchBlessing.injectablsteroids._yellowTintFrames - 1
            
            -- 효과가 끝나면 원래 색상으로 복원 (하지만 누적된 노란색은 유지)
            if ConchBlessing.injectablsteroids._yellowTintFrames <= 0 then
                -- 누적된 노란색 강도는 유지하되, 기본 색상으로 복원
                local baseColor = Color(1, 1, 1, 1, 0, 0, 0)
                if ConchBlessing.injectablsteroids._yellowIntensity and ConchBlessing.injectablsteroids._yellowIntensity > 0 then
                    -- 누적된 노란색 적용
                    baseColor = Color(
                        1 + (0.3 * ConchBlessing.injectablsteroids._yellowIntensity),
                        1 + (0.2 * ConchBlessing.injectablsteroids._yellowIntensity),
                        1 - (0.1 * ConchBlessing.injectablsteroids._yellowIntensity),
                        1,
                        0.3 * ConchBlessing.injectablsteroids._yellowIntensity,
                        0.2 * ConchBlessing.injectablsteroids._yellowIntensity,
                        -0.1 * ConchBlessing.injectablsteroids._yellowIntensity
                    )
                end
                player:SetColor(baseColor, 0, 0, false, false)
            end
        end
    end
end