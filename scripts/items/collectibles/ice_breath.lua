ConchBlessing.icebreath = {}

local game = Game()
local ICE_CANDLE_ID = Isaac.GetItemIdByName("Ice Breath")
local FIRE_CANDLE_ID = Isaac.GetItemIdByName("Fire Breath")

ConchBlessing.icebreath.data = {
    damageCoef = 0.3, -- 데미지의 30%
    flameCount = 20, -- 발사할 불꽃 수
    flameLifetime = 30, -- 불꽃 지속시간
    freezeChance = 0.2, -- 동결 확률
}

local function getPlayerData(player)
    local data = player:GetData()
    if not data.__ConchIceBreath then
        data.__ConchIceBreath = {
            hasHiddenLung = false,
            lastDirection = Vector(1, 0),
        }
    end
    return data.__ConchIceBreath
end

local function getFireDirection(player, pData)
    local dir = player:GetAimDirection()
    if dir.X ~= 0 or dir.Y ~= 0 then
        dir = dir:Normalized()
        pData.lastDirection = dir
        return dir
    end
    return pData.lastDirection or Vector(1, 0)
end

-- 눈물 발사 시 차징된 눈물을 얼음 불꽃으로 변환
ConchBlessing.icebreath.onFireTear = function(_, tear)
    local player = tear.SpawnerEntity and tear.SpawnerEntity:ToPlayer()
    if not player or not player:HasCollectible(ICE_CANDLE_ID) then return end
    
    -- 눈물 제거하고 얼음 불꽃으로 변환
    local direction = tear.Velocity:Normalized()
    if direction:Length() < 0.1 then
        direction = Vector(1, 0)
    end
    
    local stackCount = player:GetCollectibleNum(ICE_CANDLE_ID)
    local damage = (player.Damage or 1) * ConchBlessing.icebreath.data.damageCoef * stackCount
    
    -- 눈물 속도에 따라 불꽃 발사
    local speed = tear.Velocity:Length()
    local spreadAngle = (math.random() - 0.5) * 0.3
    local cosA = math.cos(spreadAngle)
    local sinA = math.sin(spreadAngle)
    local spreadDir = Vector(
        direction.X * cosA - direction.Y * sinA,
        direction.X * sinA + direction.Y * cosA
    )
    
    local flame = Isaac.Spawn(
        EntityType.ENTITY_EFFECT,
        EffectVariant.BLUE_FLAME,
        0,
        tear.Position,
        spreadDir * speed * 1.5,
        player
    ):ToEffect()
    
    if flame then
        flame:SetTimeout(ConchBlessing.icebreath.data.flameLifetime)
        flame.CollisionDamage = damage
        flame.SpriteScale = Vector(0.8, 0.8)
        
        -- 얼음 색상 설정 (파랑/청록)
        local color = Color(0.3, 0.7, 1.0, 1.0, 0, 0, 0)
        flame:SetColor(color, -1, 1, false, false)
        
        -- 데이터 저장 (동결 효과용)
        local fdata = flame:GetData()
        fdata.__ConchIceBreath = {
            source = player,
            baseDamage = damage,
            freezeChance = ConchBlessing.icebreath.data.freezeChance + (player.Luck or 0) * 0.02,
        }
    end
    
    tear:Remove()
end

ConchBlessing.icebreath.onPlayerUpdate = function(_, player)
    if not player then return end
    local hasIce = player:HasCollectible(ICE_CANDLE_ID)
    local hasFire = player:HasCollectible(FIRE_CANDLE_ID)
    
    local pData = getPlayerData(player)
    
    -- 몬스트로의 폐를 숨겨서 부여 (차징 시스템 활용)
    if hasIce and not pData.hasHiddenLung then
        if ConchBlessing.HiddenItemManager then
            ConchBlessing.HiddenItemManager:Add(player, CollectibleType.COLLECTIBLE_MONSTROS_LUNG)
            pData.hasHiddenLung = true
        end
    elseif not hasIce and pData.hasHiddenLung then
        if ConchBlessing.HiddenItemManager then
            ConchBlessing.HiddenItemManager:Remove(player, CollectibleType.COLLECTIBLE_MONSTROS_LUNG)
            pData.hasHiddenLung = false
        end
    end
end

-- 얼음 불꽃 충돌 처리 (동결 효과)
ConchBlessing.icebreath.onEffectUpdate = function(_, effect)
    if not effect then return end
    local data = effect:GetData()
    if not data or not data.__ConchIceBreath then return end
    
    -- 충돌 체크
    local entities = Isaac.GetRoomEntities()
    for _, ent in ipairs(entities) do
        if ent.Type == EntityType.ENTITY_MONSTER or (ent:ToNPC() and ent:IsVulnerableEnemy()) then
            local dist = effect.Position:Distance(ent.Position)
            if dist < 30 then
                local source = data.__ConchIceBreath.source or effect
                local damage = data.__ConchIceBreath.baseDamage or 1
                
                -- 데미지 적용
                ent:TakeDamage(damage, 0, EntityRef(source), 0)
                
                -- 동결 확률 적용
                local freezeChance = data.__ConchIceBreath.freezeChance or 0.2
                if math.random() < freezeChance then
                    local npc = ent:ToNPC()
                    if npc then
                        npc:AddFreeze(EntityRef(source), 60)
                        if EntityFlag and EntityFlag.FLAG_ICE then
                            npc:AddEntityFlags(EntityFlag.FLAG_ICE)
                        end
                        npc:SetColor(Color(0.5, 0.8, 1.0, 1.0, 0, 0, 0), 60, 1, false, true)
                    end
                end
            end
        end
    end
end

return ConchBlessing.icebreath