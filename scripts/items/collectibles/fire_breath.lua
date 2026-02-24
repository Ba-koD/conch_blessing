ConchBlessing.firebreath = {}

local game = Game()
local FIRE_CANDLE_ID = Isaac.GetItemIdByName("Fire Breath")
local ICE_CANDLE_ID = Isaac.GetItemIdByName("Ice Breath")

ConchBlessing.firebreath.data = {
    damageCoef = 0.6, -- 데미지의 60%
    flameCount = 20, -- 발사할 불꽃 수
    flameLifetime = 30, -- 불꽃 지속시간
}

local function getPlayerData(player)
    local data = player:GetData()
    if not data.__ConchFireBreath then
        data.__ConchFireBreath = {
            hasHiddenLung = false,
            lastDirection = Vector(1, 0),
        }
    end
    return data.__ConchFireBreath
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

local function spawnFireFlames(player, direction, stackCount)
    local damage = (player.Damage or 1) * ConchBlessing.firebreath.data.damageCoef * stackCount
    
    for i = 1, ConchBlessing.firebreath.data.flameCount do
        local spreadAngle = (math.random() - 0.5) * 0.8
        local cosA = math.cos(spreadAngle)
        local sinA = math.sin(spreadAngle)
        local spreadDir = Vector(
            direction.X * cosA - direction.Y * sinA,
            direction.X * sinA + direction.Y * cosA
        )
        
        local speed = 8 + math.random() * 4
        local vel = spreadDir * speed
        
        local flame = Isaac.Spawn(
            EntityType.ENTITY_EFFECT,
            EffectVariant.BLUE_FLAME,
            0,
            player.Position + direction * 10,
            vel,
            player
        ):ToEffect()
        
        if flame then
            flame:SetTimeout(ConchBlessing.firebreath.data.flameLifetime + math.random(0, 10))
            flame.CollisionDamage = damage
            flame.SpriteScale = Vector(0.8, 0.8)
            
            local color = Color(1.0, 0.5, 0.1, 1.0, 0, 0, 0)
            flame:SetColor(color, -1, 1, false, false)
            
            local fdata = flame:GetData()
            fdata.__ConchFireBreath = {
                source = player,
                baseDamage = damage,
            }
        end
    end
    
    SFXManager():Play(SoundEffect.SOUND_FLAMETHROWER_END, 1.0, 0, false, 0.8)
end

-- 눈물 발사 시 차징된 눈물을 불꽃으로 변환
ConchBlessing.firebreath.onFireTear = function(_, tear)
    local player = tear.SpawnerEntity and tear.SpawnerEntity:ToPlayer()
    if not player or not player:HasCollectible(FIRE_CANDLE_ID) then return end
    
    -- 눈물 제거하고 불꽃으로 변환
    local direction = tear.Velocity:Normalized()
    if direction:Length() < 0.1 then
        direction = Vector(1, 0)
    end
    
    local stackCount = player:GetCollectibleNum(FIRE_CANDLE_ID)
    local damage = (player.Damage or 1) * ConchBlessing.firebreath.data.damageCoef * stackCount
    
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
        flame:SetTimeout(ConchBlessing.firebreath.data.flameLifetime)
        flame.CollisionDamage = damage
        flame.SpriteScale = Vector(0.8, 0.8)
        
        local color = Color(1.0, 0.5, 0.1, 1.0, 0, 0, 0)
        flame:SetColor(color, -1, 1, false, false)
    end
    
    tear:Remove()
end

ConchBlessing.firebreath.onPlayerUpdate = function(_, player)
    if not player then return end
    local hasFire = player:HasCollectible(FIRE_CANDLE_ID)
    local hasIce = player:HasCollectible(ICE_CANDLE_ID)
    
    local pData = getPlayerData(player)
    
    -- 몬스트로의 폐를 숨겨서 부여 (차징 시스템 활용)
    if hasFire and not pData.hasHiddenLung then
        if ConchBlessing.HiddenItemManager then
            ConchBlessing.HiddenItemManager:Add(player, CollectibleType.COLLECTIBLE_MONSTROS_LUNG)
            pData.hasHiddenLung = true
        end
    elseif not hasFire and pData.hasHiddenLung then
        if ConchBlessing.HiddenItemManager then
            ConchBlessing.HiddenItemManager:Remove(player, CollectibleType.COLLECTIBLE_MONSTROS_LUNG)
            pData.hasHiddenLung = false
        end
    end
end

return ConchBlessing.firebreath