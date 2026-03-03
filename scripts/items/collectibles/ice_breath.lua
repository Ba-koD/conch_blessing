ConchBlessing.icebreath = {}

local ICE_BREATH_ID = Isaac.GetItemIdByName("Ice Breath")

-- API refs checked:
-- - EffectVariant.BLUE_FLAME (10)
local ICE_EFFECT_VARIANT = (EffectVariant and EffectVariant.BLUE_FLAME) or 10

ConchBlessing.icebreath.data = {
    damageCoef = 0.2, -- 데미지의 20%
    freezeChance = 0.0, -- fallback chance (actual: Luck%)
    lingerFrames = 30, -- 사거리 도달 후 잔류 프레임
    slowdownDistance = 36, -- 사거리 근처 감속 거리
    postRangeDrag = 0.88, -- 사거리 도달 후 감속 계수
    flameAnimationPath = "gfx/effects/flame.anm2",
    -- "tear_flame" | "entity_flame" | "entity_effect"
    projectileMode = "tear_flame",
    startScale = 0.55, -- 생성 시 작은 불꽃 크기
    endScale = 1.0, -- 이동하며 커지는 불꽃 크기
}

ConchBlessing.icebreath._isSpawningInternal = false

local ICE_BASE_COLOR = { r = 0.45, g = 0.78, b = 1.0, ro = 0.0, go = 0.0, bo = 0.0 }

local function getPlayerData(player)
    local data = player:GetData()
    if not data.__ConchIceBreath then
        data.__ConchIceBreath = {
            tearCount = 0,
        }
    end
    return data.__ConchIceBreath
end

local function clamp(value, minValue, maxValue)
    if value < minValue then return minValue end
    if value > maxValue then return maxValue end
    return value
end

local function getProjectileMode()
    local mode = ConchBlessing.icebreath.data.projectileMode
    if mode == "entity_flame" or mode == "entity_effect" or mode == "tear_flame" then
        return mode
    end
    return "tear_flame"
end

local function getFireInterval(luck)
    local interval = math.floor(15 - luck)
    if interval < 1 then
        interval = 1
    end
    return interval
end

local function getFlameCountFromTears(player)
    local maxFireDelay = math.max(0, player.MaxFireDelay or 10)
    local tearsRate = 30 / (maxFireDelay + 1)
    return math.max(1, math.floor(tearsRate))
end

local function getFlameSpeedMultiplier(player)
    return clamp(player.ShotSpeed or 1.0, 0.7, 1.6)
end

local function getFlameTravelDistance(player)
    return math.max(80, player.TearRange or 260)
end

local function getFreezeChance(player)
    local luck = (player and player.Luck) or 0
    return clamp(luck, 0, 100) / 100
end

local GRID_TILE_SIZE = 40
local GRID_SCAN_RADIUS = 26
local GRID_INTERACTION_TICK = 3

local function resolveGridType(...)
    local t = GridEntityType or {}
    for _, rawName in ipairs({ ... }) do
        local name = tostring(rawName)
        local id = t["GRID_" .. name] or t[name]
        if type(id) == "number" then
            return id
        end
    end
    return nil
end

local GRID_TYPE_TNT = resolveGridType("TNT") or 12
local GRID_TYPE_FIREPLACE = resolveGridType("FIREPLACE") or 13
local GRID_TYPE_POOP = resolveGridType("POOP") or 14

local function isInteractableGridType(gridType)
    return gridType == GRID_TYPE_TNT
        or gridType == GRID_TYPE_FIREPLACE
        or gridType == GRID_TYPE_POOP
end

local function destroyGridAt(room, gridIndex, sourceEntity)
    local grid = room and room:GetGridEntity(gridIndex)
    if not grid then
        return false
    end

    local gridType = (grid.GetType and grid:GetType()) or -1
    if gridType == GRID_TYPE_TNT then
        local ok = false
        if room.DestroyGrid then
            ok = pcall(function()
                room:DestroyGrid(gridIndex, true)
            end)
        end

        local stillTnt = false
        local after = room:GetGridEntity(gridIndex)
        if after and after.GetType then
            stillTnt = (after:GetType() == GRID_TYPE_TNT)
        end
        if stillTnt then
            local pos = room:GetGridPosition(gridIndex)
            if pos then
                pcall(function()
                    Isaac.Explode(pos, sourceEntity or Isaac.GetPlayer(0), 40)
                end)
            end
            pcall(function()
                room:RemoveGridEntity(gridIndex, 0, false)
            end)
            return true
        end

        return ok
    end

    if room.DestroyGrid then
        local ok = pcall(function()
            room:DestroyGrid(gridIndex, false)
        end)
        if ok then
            return true
        end
    end

    if room.RemoveGridEntity then
        local ok = pcall(function()
            room:RemoveGridEntity(gridIndex, 0, false)
        end)
        if ok then
            return true
        end
    end

    return false
end

local function interactProjectileWithGrids(projectile, breathData)
    local room = Game():GetRoom()
    if not room then
        return
    end

    breathData.gridTouchedAt = breathData.gridTouchedAt or {}
    local touchedAt = breathData.gridTouchedAt
    local now = Game():GetFrameCount()
    local sourceEntity = breathData.source or projectile

    local gridWidth = room:GetGridWidth() or 0
    local gridSize = room:GetGridSize() or 0
    if gridWidth <= 0 or gridSize <= 0 then
        return
    end

    local probePositions = { projectile.Position }
    local velocity = projectile.Velocity or Vector.Zero
    if velocity:Length() > 0.1 then
        probePositions[#probePositions + 1] = projectile.Position + velocity:Resized(14)
    end

    local gridRadius = math.max(1, math.ceil(GRID_SCAN_RADIUS / GRID_TILE_SIZE))
    for _, probePos in ipairs(probePositions) do
        local centerIndex = room:GetGridIndex(probePos)
        if centerIndex and centerIndex >= 0 then
            for dy = -gridRadius, gridRadius do
                for dx = -gridRadius, gridRadius do
                    local gridIndex = centerIndex + dx + (dy * gridWidth)
                    if gridIndex >= 0 and gridIndex < gridSize then
                        local last = touchedAt[gridIndex]
                        if (not last) or (now - last >= GRID_INTERACTION_TICK) then
                            local grid = room:GetGridEntity(gridIndex)
                            if grid then
                                local gridType = (grid.GetType and grid:GetType()) or -1
                                if isInteractableGridType(gridType) then
                                    local gridPos = room:GetGridPosition(gridIndex)
                                    if gridPos and gridPos:Distance(probePos) <= (GRID_SCAN_RADIUS + GRID_TILE_SIZE * 0.55) then
                                        if destroyGridAt(room, gridIndex, sourceEntity) then
                                            touchedAt[gridIndex] = now
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end

local function makeMotionState(origin, direction, speed, maxDistance)
    local lingerFrames = ConchBlessing.icebreath.data.lingerFrames or 30
    local travelFrames = math.ceil(maxDistance / math.max(0.1, speed))
    local life = math.max(12, travelFrames + lingerFrames + math.random(0, 10))
    return {
        origin = Vector(origin.X, origin.Y),
        travelDir = Vector(direction.X, direction.Y),
        maxDistance = maxDistance,
        initialSpeed = speed,
        reachedRange = false,
        slowdownDistance = ConchBlessing.icebreath.data.slowdownDistance or 36,
        driftSpeed = math.max(0.2, speed * 0.08),
        postRangeDrag = ConchBlessing.icebreath.data.postRangeDrag or 0.88,
        lifeLeft = life,
        maxLife = life,
    }
end

local function attachMotionState(targetData, motionState)
    for k, v in pairs(motionState) do
        targetData[k] = v
    end
end

local function updateProjectileMotion(projectile, breathData)
    if not breathData.lifeLeft then
        return true
    end

    breathData.lifeLeft = breathData.lifeLeft - 1
    if breathData.lifeLeft <= 0 then
        return false
    end

    local origin = breathData.origin
    local travelDir = breathData.travelDir
    local maxDistance = breathData.maxDistance
    if not (origin and travelDir and maxDistance) then
        return true
    end

    local traveled = (projectile.Position - origin):Length()
    if not breathData.reachedRange then
        local remaining = maxDistance - traveled
        if remaining <= 0 then
            breathData.reachedRange = true
            projectile.Position = origin + travelDir * maxDistance
            projectile.Velocity = travelDir * (breathData.driftSpeed or 0.2)
        else
            local progress = clamp(traveled / math.max(1, maxDistance), 0, 1)
            local speedRatio = 1.0 - progress * 0.55
            local slowdownDistance = breathData.slowdownDistance or 36
            if remaining < slowdownDistance then
                local nearEndRatio = clamp(remaining / slowdownDistance, 0.25, 1.0)
                speedRatio = speedRatio * nearEndRatio
            end
            speedRatio = clamp(speedRatio, 0.2, 1.0)
            local targetSpeed = math.max(0.2, (breathData.initialSpeed or 1.0) * speedRatio)
            local targetVelocity = travelDir * targetSpeed
            projectile.Velocity = projectile.Velocity * 0.6 + targetVelocity * 0.4
        end
    else
        projectile.Velocity = projectile.Velocity * (breathData.postRangeDrag or 0.88)
        if projectile.Velocity:Length() < 0.08 then
            projectile.Velocity = Vector.Zero
        end
    end

    return true
end

local function applyFadeColor(projectile, breathData)
    local maxLife = breathData.maxLife or 0
    if maxLife <= 0 then
        return
    end

    local ratio = clamp((breathData.lifeLeft or 0) / maxLife, 0, 1)
    local alpha = clamp(0.2 + ratio * 0.8, 0.2, 1.0)
    projectile:SetColor(
        Color(ICE_BASE_COLOR.r, ICE_BASE_COLOR.g, ICE_BASE_COLOR.b, alpha, ICE_BASE_COLOR.ro, ICE_BASE_COLOR.go, ICE_BASE_COLOR.bo),
        1,
        1,
        false,
        false
    )
end

local function applyProjectileScale(projectile, breathData, isTear)
    local startScale = breathData.startScale
    local endScale = breathData.endScale
    if (not startScale) or (not endScale) then
        return
    end

    local progress = nil
    if breathData.origin and breathData.maxDistance and breathData.maxDistance > 0 then
        local traveled = (projectile.Position - breathData.origin):Length()
        progress = clamp(traveled / breathData.maxDistance, 0, 1)
    else
        local maxLife = breathData.maxLife or 0
        if maxLife <= 0 then
            return
        end
        progress = 1 - clamp((breathData.lifeLeft or 0) / maxLife, 0, 1)
    end

    local scale = startScale + (endScale - startScale) * progress
    if isTear then
        projectile.Scale = scale
    else
        projectile.SpriteScale = Vector(scale, scale)
    end
end

local function spawnEffectFlame(player, position, velocity, direction, speed, damage, targetDistance, mode)
    local variant = ICE_EFFECT_VARIANT
    local effect = Isaac.Spawn(EntityType.ENTITY_EFFECT, variant, 0, position, velocity, player):ToEffect()
    if not effect then
        return
    end

    local motionState = makeMotionState(position, direction, speed, targetDistance)
    effect:SetTimeout(motionState.lifeLeft)
    effect.Timeout = motionState.lifeLeft
    local startScale = ConchBlessing.icebreath.data.startScale or 0.55
    local endScale = ConchBlessing.icebreath.data.endScale or 1.0
    effect.CollisionDamage = damage
    effect.SpriteScale = Vector(startScale, startScale)
    effect.GridCollisionClass = EntityGridCollisionClass.GRIDCOLL_NONE
    effect:SetColor(Color(ICE_BASE_COLOR.r, ICE_BASE_COLOR.g, ICE_BASE_COLOR.b, 1.0, ICE_BASE_COLOR.ro, ICE_BASE_COLOR.go, ICE_BASE_COLOR.bo), -1, 1, false, false)

    local sprite = effect:GetSprite()
    if sprite and mode == "entity_effect" and ConchBlessing.icebreath.data.flameAnimationPath then
        sprite:Load(ConchBlessing.icebreath.data.flameAnimationPath, true)
        sprite:Play("Idle", true)
    end

    local fdata = effect:GetData()
    fdata.__ConchIceBreath = {
        source = player,
        baseDamage = damage,
        freezeChance = getFreezeChance(player),
        projectileMode = mode,
        startScale = startScale,
        endScale = endScale,
    }
    attachMotionState(fdata.__ConchIceBreath, motionState)
end

local function spawnTearFlame(player, position, velocity, direction, speed, damage, targetDistance)
    -- Keep signature to avoid touching current fire logic/count call sites.
    local _ = direction
    _ = speed
    _ = targetDistance

    local legacyVariant = ICE_EFFECT_VARIANT
    local flame = Isaac.Spawn(
        EntityType.ENTITY_EFFECT,
        legacyVariant,
        0,
        position,
        velocity * 1.5,
        player
    ):ToEffect()
    if not flame then
        return
    end

    local timeout = 30 + math.random(0, 10)
    flame:SetTimeout(timeout)
    flame.Timeout = timeout
    flame.CollisionDamage = damage
    flame.SpriteScale = Vector(0.8, 0.8)
    flame.GridCollisionClass = EntityGridCollisionClass.GRIDCOLL_NONE
    flame:SetColor(Color(ICE_BASE_COLOR.r, ICE_BASE_COLOR.g, ICE_BASE_COLOR.b, 1.0, ICE_BASE_COLOR.ro, ICE_BASE_COLOR.go, ICE_BASE_COLOR.bo), -1, 1, false, false)

    local fdata = flame:GetData()
    fdata.__ConchIceBreath = {
        source = player,
        baseDamage = damage,
        freezeChance = getFreezeChance(player),
        -- Keep non-manual damage path like old behavior.
        projectileMode = "entity_flame",
    }
end

local function spawnIceProjectiles(player, direction)
    local stackCount = player:GetCollectibleNum(ICE_BREATH_ID)
    local flameCount = getFlameCountFromTears(player)
    local damage = (player.Damage or 1) * ConchBlessing.icebreath.data.damageCoef * stackCount
    local flameSpeedMultiplier = getFlameSpeedMultiplier(player)
    local targetDistance = getFlameTravelDistance(player)
    local mode = getProjectileMode()

    local spawningTearMode = (mode == "tear_flame")
    if spawningTearMode then
        ConchBlessing.icebreath._isSpawningInternal = true
        ConchBlessing.__ConchBreathSpawning = true
    end

    for _ = 1, flameCount do
        local spreadAngle = (math.random() - 0.5) * 0.8
        local cosA = math.cos(spreadAngle)
        local sinA = math.sin(spreadAngle)
        local spreadDir = Vector(
            direction.X * cosA - direction.Y * sinA,
            direction.X * sinA + direction.Y * cosA
        )

        local speed = (8 + math.random() * 4) * flameSpeedMultiplier
        local velocity = spreadDir * speed
        local spawnPos = player.Position + direction * 10

        if mode == "tear_flame" then
            spawnTearFlame(player, spawnPos, velocity, spreadDir, speed, damage, targetDistance)
        else
            spawnEffectFlame(player, spawnPos, velocity, spreadDir, speed, damage, targetDistance, mode)
        end
    end

    if spawningTearMode then
        ConchBlessing.icebreath._isSpawningInternal = false
        ConchBlessing.__ConchBreathSpawning = false
    end

    SFXManager():Play(SoundEffect.SOUND_FLAMETHROWER_END, 1.0, 0, false, 0.8)
end

ConchBlessing.icebreath.onFireTear = function(_, tear)
    if ConchBlessing.icebreath._isSpawningInternal or ConchBlessing.__ConchBreathSpawning then
        return
    end

    local tearData = tear:GetData()
    if tearData and tearData.__ConchIceBreath then
        return
    end

    local player = tear.SpawnerEntity and tear.SpawnerEntity:ToPlayer()
    if not player or not player:HasCollectible(ICE_BREATH_ID) then return end

    local pData = getPlayerData(player)
    local interval = getFireInterval(player.Luck or 0)
    pData.tearCount = (pData.tearCount or 0) + 1

    if pData.tearCount >= interval then
        pData.tearCount = 0
        local direction = tear.Velocity:Normalized()
        if direction:Length() < 0.1 then
            direction = Vector(1, 0)
        end
        spawnIceProjectiles(player, direction)
    end
end

ConchBlessing.icebreath.onPlayerUpdate = function(_, player)
    if not player then return end
    if not player:HasCollectible(ICE_BREATH_ID) then
        local pData = getPlayerData(player)
        pData.tearCount = 0
    end
end

ConchBlessing.icebreath.onEffectUpdate = function(_, effect)
    if not effect then return end
    local data = effect:GetData()
    if not data or not data.__ConchIceBreath then return end

    local breathData = data.__ConchIceBreath
    if not updateProjectileMotion(effect, breathData) then
        effect:Remove()
        return
    end
    applyFadeColor(effect, breathData)
    applyProjectileScale(effect, breathData, false)
    interactProjectileWithGrids(effect, breathData)

    local applyManualDamage = (breathData.projectileMode == "entity_effect")
    local entities = Isaac.GetRoomEntities()
    for _, ent in ipairs(entities) do
        local npc = ent:ToNPC()
        if npc and npc:IsVulnerableEnemy() then
            local dist = effect.Position:Distance(npc.Position)
            if dist < 30 then
                local source = breathData.source or effect
                local damage = breathData.baseDamage or 1
                if applyManualDamage then
                    npc:TakeDamage(damage, 0, EntityRef(source), 0)
                end
                if math.random() < (breathData.freezeChance or ConchBlessing.icebreath.data.freezeChance) then
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

ConchBlessing.icebreath.onTearUpdate = function(_, tear)
    if not tear then return end
    local data = tear:GetData()
    if not data or not data.__ConchIceBreath then return end

    if not updateProjectileMotion(tear, data.__ConchIceBreath) then
        tear:Remove()
        return
    end
    local breathData = data.__ConchIceBreath
    applyFadeColor(tear, breathData)
    applyProjectileScale(tear, breathData, true)
    interactProjectileWithGrids(tear, breathData)
end

ConchBlessing.icebreath.onTearCollision = function(_, tear, collider, _)
    if not (tear and collider) then return nil end
    local data = tear:GetData()
    if not data or not data.__ConchIceBreath then return nil end

    local npc = collider:ToNPC()
    if not (npc and npc:IsVulnerableEnemy()) then return nil end

    local breathData = data.__ConchIceBreath
    local source = breathData.source or tear
    if math.random() < (breathData.freezeChance or ConchBlessing.icebreath.data.freezeChance) then
        npc:AddFreeze(EntityRef(source), 60)
        if EntityFlag and EntityFlag.FLAG_ICE then
            npc:AddEntityFlags(EntityFlag.FLAG_ICE)
        end
        npc:SetColor(Color(0.5, 0.8, 1.0, 1.0, 0, 0, 0), 60, 1, false, true)
    end

    return nil
end

return ConchBlessing.icebreath
