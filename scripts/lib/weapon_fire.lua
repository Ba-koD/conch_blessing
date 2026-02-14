--[[
    Weapon Fire Utility
    
    Eye Sore의 FireMimicAttack을 라이브러리로 분리
    
    Usage:
        local WeaponFire = require("scripts.lib.weapon_fire")
        
        -- 기본 사용 (단일 발사)
        WeaponFire.Fire(player, angle, pType, sourceEntity)
        
        -- REPENTOGON 사용 시 (멀티샷 패턴 적용)
        WeaponFire.FireMulti(player, direction, count)
        
        pType: "tear" | "laser" | "knife" | "bomb"
        sourceEntity: 원본 공격 엔티티 (눈물, 레이저 등)
]]

local game = Game()
local WeaponFire = {}

-- 무한루프 방지 플래그
local _firing = false

-- Technology 2(보조 레이저) 예외 처리용
local TECH2_ID = (CollectibleType and CollectibleType.COLLECTIBLE_TECHNOLOGY_2) or -1
if (not TECH2_ID) or TECH2_ID <= 0 then
    TECH2_ID = Isaac.GetItemIdByName("Technology 2")
    if (not TECH2_ID) or TECH2_ID <= 0 then
        TECH2_ID = Isaac.GetItemIdByName("Tech 2")
    end
end
local LASER_TECH2 = (LaserVariant and LaserVariant.LASER_TECH2) or -1

-- Technology 0(Tech Zero) 예외 처리용
local TECH0_ID = (CollectibleType and CollectibleType.COLLECTIBLE_TECHNOLOGY_ZERO) or -1
if (not TECH0_ID) or TECH0_ID <= 0 then
    TECH0_ID = Isaac.GetItemIdByName("Tech Zero")
    if (not TECH0_ID) or TECH0_ID <= 0 then
        TECH0_ID = Isaac.GetItemIdByName("Technology Zero")
    end
end

---단일 공격 발사 (내부 함수)
---@param player EntityPlayer
---@param pos Vector 발사 위치
---@param vel Vector 발사 속도
---@param pType string
---@param sourceEntity Entity?
---@param copyTearFunc function?
---@return Entity?
local function fireSingle(player, pos, vel, pType, sourceEntity, copyTearFunc)
    local angle = vel:GetAngleDegrees()
    local dirV = vel:Normalized()
    local sSpeed = vel:Length() / 10
    local damage = player.Damage
    local flags = player.TearFlags
    local pRange = player.Range or 400
    
    local wType = 1
    if player.GetWeaponType then wType = player:GetWeaponType() end
    
    local sourceLaser = sourceEntity and sourceEntity:ToLaser()
    local laserVariant = sourceLaser and sourceLaser.Variant or 1
    local laserTimeout = sourceLaser and sourceLaser.Timeout or 20
    
    local hasTech2 = (TECH2_ID and TECH2_ID > 0) and player:HasCollectible(TECH2_ID)
    local isTech2Laser = (laserVariant == LASER_TECH2)
    local forceTearForTech2 = hasTech2 or isTech2Laser
    
    local hasTech0 = (TECH0_ID and TECH0_ID > 0) and player:HasCollectible(TECH0_ID)
    local isTech0Laser = false
    if sourceLaser and sourceLaser.IsCircleLaser and sourceLaser:IsCircleLaser() then
        isTech0Laser = (sourceLaser.SubType == 4)
    end
    local forceTearForTech0 = hasTech0 or isTech0Laser
    
    local entity = nil
    
    -- 1) Tech X
    local isTechXRing = false
    if sourceLaser and sourceLaser.IsCircleLaser and sourceLaser:IsCircleLaser() then
        isTechXRing = (sourceLaser.SubType == 2)
    end
    
    if wType == 9 or isTechXRing then
        local radius = sourceLaser and sourceLaser.Radius or 30
        local l = player:FireTechXLaser(pos, vel, radius, player, 1.0)
        if l then
            l.TearFlags = flags
            l.CollisionDamage = damage
            if player.LaserColor then l.Color = player.LaserColor end
            local ld = l:GetData()
            ld.__is_extra_attack = true
            ld.__is_moving_laser = true
            l.MaxDistance = pRange
        end
        entity = l
    
    -- 2) Brimstone
    elseif wType == 2
       or (sourceEntity and (sourceEntity.Variant == 1 or sourceEntity.Variant == 5 or sourceEntity.Variant == 9 or sourceEntity.Variant == 11))
       or (wType == 3 and player:HasCollectible(CollectibleType.COLLECTIBLE_BRIMSTONE)) then
        
        local l = player:FireBrimstone(dirV, player, 1.0)
        if l then
            l.TearFlags = flags
            l.CollisionDamage = damage
            if player.LaserColor then l.Color = player.LaserColor end
            
            local ld = l:GetData()
            ld.__is_extra_attack = true
            ld.__parent_laser = sourceEntity
            l.Timeout = laserTimeout
            
            if sourceLaser then
                ld.__initial_parent_angle = sourceLaser.Angle
                ld.__initial_mimic_angle = l.Angle
            end
        end
        entity = l
    
    -- 3) Technology
    elseif (wType == 3 or pType == "laser") and (not forceTearForTech2) and (not forceTearForTech0) then
        local l = player:FireTechLaser(pos, 0, dirV, true, true, player, 1.0)
        if l then
            l.TearFlags = flags
            l.CollisionDamage = damage
            if player.LaserColor then l.Color = player.LaserColor end
            l.OneHit = true
            l:GetData().__is_extra_attack = true
            
            if sourceLaser and sourceLaser.Timeout then
                l.Timeout = sourceLaser.Timeout
            end
        end
        entity = l
    
    -- 4) Mom's Knife
    elseif wType == 4 or pType == "knife" then
        local v = (sourceEntity and sourceEntity.Variant) or 0
        local s = (sourceEntity and sourceEntity.SubType) or 0
        local knifeObj = sourceEntity and sourceEntity:ToKnife()
        local charge = knifeObj and knifeObj.Charge or 1.0
        
        local k_ent = player:FireKnife(player, angle, false, v, s)
        local k = k_ent and k_ent:ToKnife()
        if k then
            k.CollisionDamage = damage * 2
            k.TearFlags = flags
            if sourceEntity and sourceEntity.Color then k.Color = sourceEntity.Color end
            
            if k.SetPathFollowSpeed then
                k:SetPathFollowSpeed(0.12 * sSpeed)
            end
            
            local kd = k:GetData()
            kd.__is_extra_attack = true
            kd.__extra_spawn_frame = game:GetFrameCount()
            
            if k.Shoot then
                local finalRange = pRange * 0.38 * sSpeed
                k:Shoot(charge, finalRange)
            end
        end
        entity = k_ent
    
    -- 5) Dr. Fetus
    elseif wType == 5 or pType == "bomb" then
        local b = player:FireBomb(pos, vel, player)
        if b then
            b.CollisionDamage = damage
            if b.ToBomb then b:ToBomb().IsFetus = true end
            b:GetData().__is_extra_attack = true
        end
        entity = b
    
    -- 6) 기본: Tears
    else
        local srcTear = sourceEntity and sourceEntity:ToTear() or nil
        local t = player:FireTear(pos, vel, false, false, false)
        if t then
            local td = t:GetData()
            td.__is_extra_attack = true
            
            if copyTearFunc and srcTear then
                copyTearFunc(srcTear, t, damage, flags)
            else
                t.CollisionDamage = damage
                t.TearFlags = flags
                if srcTear then
                    t.Color = srcTear.Color
                    t.Scale = srcTear.Scale
                    t.Height = srcTear.Height
                    t.FallingSpeed = srcTear.FallingSpeed
                    t.FallingAcceleration = srcTear.FallingAcceleration
                    if srcTear.Variant and srcTear.Variant ~= 0 then
                        t:ChangeVariant(srcTear.Variant)
                    end
                end
            end
        end
        entity = t
    end
    
    return entity
end

---Eye Sore 스타일 공격 복제 발사 (단일)
---@param player EntityPlayer
---@param angle number 발사 각도 (degrees)
---@param pType string "tear" | "laser" | "knife" | "bomb"
---@param sourceEntity Entity? 원본 공격 엔티티
---@param copyTearFunc function? 눈물 속성 복사 함수 (optional)
---@return Entity?
function WeaponFire.Fire(player, angle, pType, sourceEntity, copyTearFunc)
    if _firing then return nil end
    _firing = true
    
    local pos = player.Position + (player.TearsOffset or Vector.Zero)
    local sSpeed = player.ShotSpeed or 1.0
    local dirV = Vector.FromAngle(angle)
    local vel = dirV:Resized(sSpeed * 10)
    
    local entity = fireSingle(player, pos, vel, pType, sourceEntity, copyTearFunc)
    
    _firing = false
    return entity
end

---REPENTOGON 멀티샷 패턴으로 여러 발 발사
---REPENTOGON이 없으면 단순히 같은 방향으로 count발 발사
---@param player EntityPlayer
---@param direction Vector 발사 방향
---@param count number 추가 발사 수
---@param pType string? "tear" | "laser" | "knife" | "bomb"
---@param sourceEntity Entity? 원본 공격 엔티티
---@return Entity[]
function WeaponFire.FireMulti(player, direction, count, pType, sourceEntity)
    if _firing then return {} end
    _firing = true
    
    local entities = {}
    local wType = 1
    if player.GetWeaponType then wType = player:GetWeaponType() end
    
    local sSpeed = player.ShotSpeed or 1.0
    local basePos = player.Position + (player.TearsOffset or Vector.Zero)
    
    -- REPENTOGON이 있으면 GetMultiShotParams 사용
    if REPENTOGON and player.GetMultiShotParams and player.GetMultiShotPositionVelocity then
        local multiParams = player:GetMultiShotParams(wType)
        local numTears = multiParams:GetNumTears()
        
        -- count만큼 추가 발사 (기존 멀티샷 패턴에 맞춰)
        for i = 0, count - 1 do
            -- 각 추가 공격마다 멀티샷 패턴의 첫 번째 위치/속도 사용
            local posVel = player:GetMultiShotPositionVelocity(i % numTears, wType, direction, sSpeed, multiParams)
            local pos = basePos + posVel.Position
            local vel = posVel.Velocity
            
            local entity = fireSingle(player, pos, vel, pType or "tear", sourceEntity)
            if entity then
                table.insert(entities, entity)
            end
        end
    else
        -- REPENTOGON 없으면 같은 방향으로 단순 발사
        local vel = direction:Resized(sSpeed * 10)
        
        for _ = 1, count do
            local entity = fireSingle(player, basePos, vel, pType or "tear", sourceEntity)
            if entity then
                table.insert(entities, entity)
            end
        end
    end
    
    _firing = false
    return entities
end

---현재 발사 중인지 확인 (무한루프 방지용)
---@return boolean
function WeaponFire.IsFiring()
    return _firing
end

return WeaponFire
