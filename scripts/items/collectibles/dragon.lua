ConchBlessing.dragon = {}

local DRAGON_ID = Isaac.GetItemIdByName("Dragon")
local VORTEX_VARIANT = (EffectVariant and EffectVariant.BRIMSTONE_BALL) or 113
local WHIRLPOOL_VARIANT = (EffectVariant and EffectVariant.WHIRLPOOL) or 142
local WHIRLPOOL_PARTICLE_SUBTYPE = 1
local BIG_WATER_SPLASH_VARIANT = (EffectVariant and EffectVariant.BIG_SPLASH) or 132
local WHIRLPOOL_SCALE_MULT = 1.2
local WHIRLPOOL_PARTICLE_SCALE_MULT = 1.5
local BIG_WATER_SPLASH_SCALE_MULT = 2.0

ConchBlessing.dragon.data = {
    attacksPerTrigger = 5,
    spawnCount = 5, -- fixed count (no stack scaling)
    projectileSpeed = 6.3, -- 70% speed baseline
    decelerationFrames = 60, -- fully stops in 60 ticks
    baseDamagePercent = 0.25, -- 25% of player damage
    synergyDamageBonus = 0.25, -- +25% per extra stack for vortex touch damage
    vortexExplosionDamageMultiplier = 25, -- whirlpool expiry explosion damage
    techXRadius = 40,
    vortexPullRadius = 220, -- whirlpool pull radius
    vortexPullStrength = 3.2, -- whirlpool pull strength
    vortexExplosionRadius = 180, -- fixed explosion radius reference
    vortexExplosionVisualDamage = 0, -- visual-only explode damage
    vortexTouchRadius = 72, -- base radius at SpriteScale 1.0
    vortexTouchTick = 1,
    vortexScale = 0.6,
    whirlpoolDurationFrames = 60, -- 2 sec at 30 FPS
    gridInteractionRadius = 60, -- fireplace/TNT interaction radius around vortex/whirlpool
    gridInteractionTick = 4, -- frames between touching the same grid index
    gridCollisionProbeOffset = 16, -- front probe distance for moving vortex
    vortexWallMode = "pierce", -- "pierce" | "stick"
}

ConchBlessing.dragon._isInternalSpawn = false
ConchBlessing.dragon._sfxCooldown = {}

-- Tech X ring texture is red-heavy, so use additive offsets to force a yellow tint.
local TECHX_COLOR = Color(1.0, 1.0, 1.0, 1.0, 0.55, 1.75, -0.05)
local VORTEX_COLOR = Color(1.0, 1.0, 1.0, 1.0, -0.75, 0.45, 1.25)

local function clamp(value, minValue, maxValue)
    if value < minValue then return minValue end
    if value > maxValue then return maxValue end
    return value
end

local function resolveSoundId(defaultId, ...)
    if SoundEffect then
        for _, rawName in ipairs({ ... }) do
            local name = tostring(rawName)
            local id = SoundEffect["SOUND_" .. name] or SoundEffect[name]
            if type(id) == "number" then
                return id
            end
        end
    end
    return defaultId
end

local SFX_WHIRL_SPAWN = resolveSoundId(474, "BOSS_2_DIVE", "WATER_FLOW_LARGE")
local SFX_WHIRL_SPAWN_ALT = resolveSoundId(426, "MAW_OF_VOID", "BOSS_2_WATER_THRASHING")
local SFX_WHIRLPOOL_SPAWN = resolveSoundId(488, "BOSS_2_WATER_THRASHING", "WATER_FLOW_LOOP", "WET_FEET")
local SFX_WHIRLPOOL_LOOP = resolveSoundId(473, "WATER_FLOW_LOOP", "WET_FEET")
local SFX_WATER_EXPLODE = resolveSoundId(486, "BOSS_2_INTRO_WATER_EXPLOSION", "BOSS_2_WATER_THRASHING")
local SFX_WATER_EXPLODE_ALT = resolveSoundId(488, "BOSS_2_WATER_THRASHING", "WAR_LAVA_SPLASH", "BEAST_LAVA_BALL_SPLASH")

local function playSfx(soundId, volume, pitch, minIntervalFrames)
    local id = tonumber(soundId)
    if not id then
        return
    end

    local interval = tonumber(minIntervalFrames) or 0
    if interval > 0 then
        local frame = Game():GetFrameCount()
        local gate = ConchBlessing.dragon._sfxCooldown or {}
        local lastFrame = gate[id]
        if lastFrame and (frame - lastFrame) < interval then
            return
        end
        gate[id] = frame
        ConchBlessing.dragon._sfxCooldown = gate
    end

    local sfx = SFXManager()
    if not sfx then
        return
    end

    local ok = pcall(function()
        sfx:Play(id, volume or 1.0, 0, false, pitch or 1.0, 0)
    end)
    if not ok then
        ok = pcall(function()
            sfx:Play(id, volume or 1.0, 0, false, pitch or 1.0)
        end)
    end
    if not ok then
        pcall(function()
            sfx:Play(id, volume or 1.0)
        end)
    end
end

local function playSfxSet(ids, volume, pitch, minIntervalFrames)
    if not ids then
        return
    end
    for _, id in ipairs(ids) do
        playSfx(id, volume, pitch, minIntervalFrames)
    end
end

local function safePlayAnimation(sprite, animation, force)
    if not (sprite and sprite.Play and animation) then
        return
    end
    pcall(function()
        sprite:Play(animation, force == true)
    end)
end

local function hasDragon(player)
    return player
        and DRAGON_ID
        and DRAGON_ID > 0
        and player.HasCollectible
        and player:HasCollectible(DRAGON_ID)
end

local function getDragonCount(player)
    if not player then
        return 0
    end

    local ok, count = pcall(function()
        return player:GetCollectibleNum(DRAGON_ID, true)
    end)
    if not ok then
        ok, count = pcall(function()
            return player:GetCollectibleNum(DRAGON_ID)
        end)
    end

    if ok and type(count) == "number" then
        return math.max(0, math.floor(count))
    end
    return 0
end

local function getPlayerData(player)
    local data = player:GetData()
    if not data.__ConchDragon then
        data.__ConchDragon = {
            attackCount = 0,
            lastAttackFrame = -1,
        }
    end
    return data.__ConchDragon
end

local function findPlayerByInitSeed(initSeed)
    if not initSeed then
        return nil
    end

    local n = Game():GetNumPlayers()
    for i = 0, n - 1 do
        local player = Isaac.GetPlayer(i)
        if player and player.InitSeed == initSeed then
            return player
        end
    end
    return nil
end

local function findEffectByInitSeed(initSeed, variant)
    if not initSeed then
        return nil
    end

    for _, entity in ipairs(Isaac.GetRoomEntities()) do
        local effect = entity:ToEffect()
        if effect and effect.InitSeed == initSeed then
            if (not variant) or effect.Variant == variant then
                return effect
            end
        end
    end
    return nil
end

local function spawnWhirlpoolParticle(position, spawner, scale, timeoutFrames)
    local particle = Isaac.Spawn(
        EntityType.ENTITY_EFFECT,
        WHIRLPOOL_VARIANT,
        WHIRLPOOL_PARTICLE_SUBTYPE,
        position,
        Vector.Zero,
        spawner
    ):ToEffect()
    if not particle then
        return nil
    end

    local particleScale = 0.3 * WHIRLPOOL_PARTICLE_SCALE_MULT
    particle.SpriteScale = Vector(particleScale, particleScale)
    particle.SpriteOffset = Vector(0, -5)
    particle.DepthOffset = 24
    safePlayAnimation(particle:GetSprite(), "Idle1", true)
    if timeoutFrames and particle.SetTimeout then
        particle:SetTimeout(timeoutFrames)
    end
    return particle
end

local function getPlayerFromEntity(entity)
    if not entity then
        return nil
    end

    local spawner = entity.SpawnerEntity
    if spawner and spawner:ToPlayer() then
        return spawner:ToPlayer()
    end

    local parent = entity.Parent
    if parent and parent:ToPlayer() then
        return parent:ToPlayer()
    end

    if parent and parent.SpawnerEntity and parent.SpawnerEntity:ToPlayer() then
        return parent.SpawnerEntity:ToPlayer()
    end

    return nil
end

local function getRandomDirection(player)
    local rng = nil
    if player and player.GetCollectibleRNG then
        local ok, collectibleRng = pcall(function()
            return player:GetCollectibleRNG(DRAGON_ID)
        end)
        if ok then
            rng = collectibleRng
        end
    end

    local angle = nil
    if rng and rng.RandomFloat then
        angle = rng:RandomFloat() * 360
    else
        angle = math.random() * 360
    end

    local direction = Vector.FromAngle(angle)
    if direction:Length() < 0.001 then
        direction = Vector(1, 0)
    end
    return direction:Resized(1)
end

local function getTechXDamage(player)
    return (player.Damage or 3.5) * (ConchBlessing.dragon.data.baseDamagePercent or 0.25)
end

local function getVortexTouchDamage(player, dragonCount)
    local playerDamage = player.Damage or 3.5
    local basePercent = ConchBlessing.dragon.data.baseDamagePercent or 0.25
    local perExtra = ConchBlessing.dragon.data.synergyDamageBonus or 0.25
    local extraStacks = math.max(0, dragonCount - 1)
    local totalPercent = basePercent + (perExtra * extraStacks)
    return playerDamage * totalPercent
end

local function getVortexExplosionDamage(player)
    local mult = ConchBlessing.dragon.data.vortexExplosionDamageMultiplier or 25
    local out = (player.Damage or 3.5) * mult
    if out < 1 then
        out = 1
    end
    return out
end

local function doSoflamStyleExplosion(player, sourceEntity, position, damage)
    local spawner = player or sourceEntity
    Isaac.Explode(position, spawner, damage)
    Game():ShakeScreen(4)
end

local function applyDragonLaserFlags(laser, player)
    local flags = laser.TearFlags or 0
    if player and player.TearFlags then
        flags = flags | player.TearFlags
    end
    if TearFlags and TearFlags.TEAR_SPECTRAL then
        flags = flags | TearFlags.TEAR_SPECTRAL
    end
    if TearFlags and TearFlags.TEAR_JACOBS then
        flags = flags | TearFlags.TEAR_JACOBS
    end
    if TearFlags and TearFlags.TEAR_ATTRACTOR then
        flags = flags | TearFlags.TEAR_ATTRACTOR
    end
    laser.TearFlags = flags
end

local function spawnTechX(player, velocity, damage)
    local playerDamage = player.Damage or 3.5
    if playerDamage <= 0 then
        playerDamage = 3.5
    end
    local damageMultiplier = damage / playerDamage
    local radius = ConchBlessing.dragon.data.techXRadius or 12

    local laser = player:FireTechXLaser(player.Position, velocity, radius, player, damageMultiplier)
    if not laser then
        return
    end

    laser.CollisionDamage = damage
    laser.Color = TECHX_COLOR
    laser:SetColor(TECHX_COLOR, -1, 1, false, false)
    local spawnSprite = laser:GetSprite()
    if spawnSprite then
        spawnSprite.Color = TECHX_COLOR
    end
    applyDragonLaserFlags(laser, player)

    local lData = laser:GetData()
    lData.__ConchDragonInternal = true
    lData.__ConchDragonTechX = {
        ownerInitSeed = player.InitSeed,
        direction = velocity:Normalized(),
        initialSpeed = velocity:Length(),
        age = 0,
        life = ConchBlessing.dragon.data.decelerationFrames or 60,
    }
end

local function spawnVortex(player, velocity, touchDamage, explosionDamage)
    local effect = Isaac.Spawn(
        EntityType.ENTITY_EFFECT,
        VORTEX_VARIANT,
        0,
        player.Position,
        velocity,
        player
    ):ToEffect()
    if not effect then
        return
    end

    local scale = ConchBlessing.dragon.data.vortexScale or 0.6
    effect.SpriteScale = Vector(scale, scale)
    effect:SetColor(VORTEX_COLOR, -1, 1, false, false)
    effect.DepthOffset = 25

    local totalLife = (ConchBlessing.dragon.data.decelerationFrames or 60) + (ConchBlessing.dragon.data.whirlpoolDurationFrames or 60) + 8
    local particle = spawnWhirlpoolParticle(player.Position, player, scale, totalLife)
    playSfxSet({ SFX_WHIRL_SPAWN, SFX_WHIRL_SPAWN_ALT }, 1.05, 1.04, 2)

    local eData = effect:GetData()
    eData.__ConchDragonVortex = {
        ownerInitSeed = player.InitSeed,
        direction = velocity:Normalized(),
        initialSpeed = velocity:Length(),
        age = 0,
        life = ConchBlessing.dragon.data.decelerationFrames or 60,
        touchDamage = touchDamage,
        explosionDamage = explosionDamage,
        pullRadius = ConchBlessing.dragon.data.vortexPullRadius or 220,
        pullStrength = ConchBlessing.dragon.data.vortexPullStrength or 0.9,
        explodeRadius = ConchBlessing.dragon.data.vortexExplosionRadius or 180,
        touchRadius = ConchBlessing.dragon.data.vortexTouchRadius or 72,
        touchTick = ConchBlessing.dragon.data.vortexTouchTick or 1,
        particleInitSeed = particle and particle.InitSeed or nil,
        touchedAt = {},
        exploded = false,
    }
end

local function spawnWhirlpool(position, vortexData)
    local owner = findPlayerByInitSeed(vortexData.ownerInitSeed)
    local spawner = owner or Isaac.GetPlayer(0)
    local effect = Isaac.Spawn(
        EntityType.ENTITY_EFFECT,
        WHIRLPOOL_VARIANT,
        0,
        position,
        Vector.Zero,
        spawner
    ):ToEffect()
    if not effect then
        return nil
    end

    local scale = (ConchBlessing.dragon.data.vortexScale or 0.6) * WHIRLPOOL_SCALE_MULT
    effect.SpriteScale = Vector(scale, scale)
    effect.Velocity = Vector.Zero
    effect.DepthOffset = 25

    local oldParticle = findEffectByInitSeed(vortexData.particleInitSeed)
    if oldParticle then
        oldParticle:Remove()
    end

    -- Spawn a fresh particle exactly when vortex transitions into whirlpool.
    local particle = spawnWhirlpoolParticle(
        position,
        spawner,
        scale,
        (ConchBlessing.dragon.data.whirlpoolDurationFrames or 60) + 8
    )

    playSfxSet({ SFX_WHIRLPOOL_SPAWN }, 1.0, 0.95, 2)

    local eData = effect:GetData()
    eData.__ConchDragonWhirlpool = {
        ownerInitSeed = vortexData.ownerInitSeed,
        age = 0,
        life = ConchBlessing.dragon.data.whirlpoolDurationFrames or 60,
        touchDamage = vortexData.touchDamage,
        explosionDamage = vortexData.explosionDamage,
        pullRadius = vortexData.pullRadius or (ConchBlessing.dragon.data.vortexPullRadius or 220),
        pullStrength = vortexData.pullStrength or (ConchBlessing.dragon.data.vortexPullStrength or 0.9),
        explodeRadius = vortexData.explodeRadius or (ConchBlessing.dragon.data.vortexExplosionRadius or 180),
        touchRadius = vortexData.touchRadius or (ConchBlessing.dragon.data.vortexTouchRadius or 72),
        touchTick = vortexData.touchTick or (ConchBlessing.dragon.data.vortexTouchTick or 1),
        particleInitSeed = particle and particle.InitSeed or nil,
        particleSpawnInterval = 15, -- 0.5 sec
        nextParticleSpawnAge = 15,
        isWhirlpool = true,
        touchedAt = {},
        exploded = false,
    }
    return effect
end

local function spawnDragonProjectiles(player)
    if not hasDragon(player) then
        return
    end

    local dragonCount = getDragonCount(player)
    if dragonCount <= 0 then
        return
    end

    local speed = ConchBlessing.dragon.data.projectileSpeed or 6.3
    local spawnCount = ConchBlessing.dragon.data.spawnCount or 5

    ConchBlessing.dragon._isInternalSpawn = true

    for _ = 1, spawnCount do
        local direction = getRandomDirection(player)
        local velocity = direction:Resized(speed)
        if dragonCount >= 2 then
            spawnVortex(
                player,
                velocity,
                getVortexTouchDamage(player, dragonCount),
                getVortexExplosionDamage(player)
            )
        else
            spawnTechX(player, velocity, getTechXDamage(player))
        end
    end

    ConchBlessing.dragon._isInternalSpawn = false
end

local function incrementAttackCount(player)
    if not hasDragon(player) then
        return
    end

    local pData = getPlayerData(player)
    local nowFrame = Game():GetFrameCount()
    if pData.lastAttackFrame == nowFrame then
        return
    end
    pData.lastAttackFrame = nowFrame
    pData.attackCount = (pData.attackCount or 0) + 1

    local trigger = ConchBlessing.dragon.data.attacksPerTrigger or 5
    if pData.attackCount >= trigger then
        pData.attackCount = 0
        spawnDragonProjectiles(player)
    end
end

local function isDamageableEnemy(npc)
    if not npc then
        return false
    end
    if npc:IsDead() then
        return false
    end
    if not npc:IsVulnerableEnemy() then
        return false
    end
    if npc:HasEntityFlags(EntityFlag.FLAG_FRIENDLY) then
        return false
    end
    return true
end

local GRID_TILE_SIZE = 40

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

local function resolveEntityType(...)
    local t = EntityType or {}
    for _, rawName in ipairs({ ... }) do
        local name = tostring(rawName)
        local id = t["ENTITY_" .. name] or t[name]
        if type(id) == "number" then
            return id
        end
    end
    return nil
end

local ENTITY_TYPE_FIREPLACE = resolveEntityType("FIREPLACE") or 33
local ENTITY_TYPE_MOVABLE_TNT = resolveEntityType("MOVABLE_TNT") or 292

local function buildBreakableGridTypeSet()
    -- Dragon vortex/grid interaction is intentionally limited:
    -- only fireplace + TNT should react (no generic rock/block breaking).
    local out = {}
    out[GRID_TYPE_TNT] = true
    out[GRID_TYPE_FIREPLACE] = true
    return out
end

local BREAKABLE_GRID_TYPE_SET = buildBreakableGridTypeSet()

local function isBreakableGrid(gridEntity)
    if not gridEntity or not gridEntity.GetType then
        return false
    end
    return BREAKABLE_GRID_TYPE_SET[gridEntity:GetType()] == true
end

local function triggerTntExplosion(room, gridIndex, sourceEntity)
    if not room then
        return false
    end

    local explosionPos = room:GetGridPosition(gridIndex)
    if not explosionPos then
        return false
    end

    local owner = sourceEntity or Isaac.GetPlayer(0)
    local didExplode = pcall(function()
        Isaac.Explode(explosionPos, owner, 40)
    end)

    pcall(function()
        room:RemoveGridEntity(gridIndex, 0, false)
    end)

    return didExplode
end

local function removeGridAtIndex(room, gridIndex, sourceEntity)
    if not (room and gridIndex and gridIndex >= 0) then
        return false
    end

    local gridEntity = room:GetGridEntity(gridIndex)
    if not gridEntity then
        return false
    end

    local gridType = (gridEntity.GetType and gridEntity:GetType()) or -1
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
            triggerTntExplosion(room, gridIndex, sourceEntity)
        end
        return ok or not stillTnt
    end
    if gridType ~= GRID_TYPE_FIREPLACE then
        return false
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

local function interactWithNearbySpecialEntities(position, radius, sourceEntity)
    local scanRadius = math.max(8, radius or (ConchBlessing.dragon.data.gridInteractionRadius or 36))
    local sourceRef = EntityRef(sourceEntity or Isaac.GetPlayer(0))
    local explodeFlags = ((DamageFlag and DamageFlag.DAMAGE_EXPLOSION) or 0)
        | ((DamageFlag and DamageFlag.DAMAGE_IGNORE_ARMOR) or 0)
    local fireFlags = ((DamageFlag and DamageFlag.DAMAGE_FIRE) or 0)
        | ((DamageFlag and DamageFlag.DAMAGE_IGNORE_ARMOR) or 0)

    for _, entity in ipairs(Isaac.GetRoomEntities()) do
        if entity and entity.Position:Distance(position) <= scanRadius then
            if entity.Type == ENTITY_TYPE_MOVABLE_TNT then
                local exploded = false
                local npc = entity:ToNPC()
                if npc then
                    exploded = pcall(function()
                        npc:TakeDamage(60, explodeFlags, sourceRef, 0)
                    end)
                end
                if (not exploded) and entity.ToBomb then
                    local bomb = entity:ToBomb()
                    if bomb and bomb.SetExplosionCountdown then
                        exploded = pcall(function()
                            bomb:SetExplosionCountdown(0)
                        end)
                    end
                end
                if not exploded then
                    pcall(function()
                        Isaac.Explode(entity.Position, sourceEntity or Isaac.GetPlayer(0), 40)
                    end)
                    pcall(function()
                        entity:Remove()
                    end)
                end
            elseif entity.Type == ENTITY_TYPE_FIREPLACE then
                local killed = false
                if entity.ToNPC then
                    local fireNpc = entity:ToNPC()
                    if fireNpc then
                        killed = pcall(function()
                            fireNpc:TakeDamage(30, fireFlags, sourceRef, 0)
                        end)
                    end
                end
                if not killed then
                    pcall(function()
                        entity:Kill()
                    end)
                end
            end
        end
    end
end

local function interactWithNearbyBreakableGrids(position, radius, runtimeData)
    local room = Game():GetRoom()
    if not room then
        return false
    end

    local centerIndex = room:GetGridIndex(position)
    if not centerIndex or centerIndex < 0 then
        return false
    end

    local gridWidth = room:GetGridWidth() or 0
    local gridSize = room:GetGridSize() or 0
    if gridWidth <= 0 or gridSize <= 0 then
        return false
    end

    local scanRadius = math.max(8, radius or (ConchBlessing.dragon.data.gridInteractionRadius or 36))
    local gridRadius = math.max(1, math.ceil(scanRadius / GRID_TILE_SIZE))
    local now = Game():GetFrameCount()
    local tick = runtimeData.gridInteractionTick or (ConchBlessing.dragon.data.gridInteractionTick or 4)
    runtimeData.gridTouchedAt = runtimeData.gridTouchedAt or {}
    local owner = findPlayerByInitSeed(runtimeData.ownerInitSeed)
    local sourceEntity = owner or Isaac.GetPlayer(0)
    interactWithNearbySpecialEntities(position, scanRadius, sourceEntity)

    local touchedAny = false
    for dy = -gridRadius, gridRadius do
        for dx = -gridRadius, gridRadius do
            local gridIndex = centerIndex + dx + (dy * gridWidth)
            if gridIndex >= 0 and gridIndex < gridSize then
                local gridEntity = room:GetGridEntity(gridIndex)
                if gridEntity and isBreakableGrid(gridEntity) then
                    local gridPos = room:GetGridPosition(gridIndex)
                    if gridPos and gridPos:Distance(position) <= (scanRadius + GRID_TILE_SIZE * 0.55) then
                        local lastTouchFrame = runtimeData.gridTouchedAt[gridIndex]
                        if (not lastTouchFrame) or (now - lastTouchFrame >= tick) then
                            if removeGridAtIndex(room, gridIndex, sourceEntity) then
                                runtimeData.gridTouchedAt[gridIndex] = now
                                touchedAny = true
                            end
                        end
                    end
                end
            end
        end
    end

    return touchedAny
end

local function isBlockingGridAt(room, position)
    if not (room and position and room.GetGridEntityFromPos) then
        return false
    end

    local gridEntity = room:GetGridEntityFromPos(position)
    if not gridEntity then
        return false
    end
    if isBreakableGrid(gridEntity) then
        return false
    end

    local c = gridEntity.CollisionClass or 0
    local objectClass = (GridCollisionClass and (GridCollisionClass.COLLISION_OBJECT or GridCollisionClass.OBJECT)) or 2
    local solidClass = (GridCollisionClass and (GridCollisionClass.COLLISION_SOLID or GridCollisionClass.SOLID)) or 3
    local wallClass = (GridCollisionClass and (GridCollisionClass.COLLISION_WALL or GridCollisionClass.WALL)) or 4
    return c == objectClass or c == solidClass or c == wallClass
end

local function handleVortexGridInteraction(effect, vortexData)
    local room = Game():GetRoom()
    if not room then
        return false
    end

    local probeOffset = ConchBlessing.dragon.data.gridCollisionProbeOffset or 16
    local velocity = effect.Velocity or Vector.Zero
    local gridRadius = ConchBlessing.dragon.data.gridInteractionRadius or 36
    interactWithNearbyBreakableGrids(effect.Position, gridRadius, vortexData)
    local probePos = effect.Position
    if velocity:Length() > 0.1 then
        probePos = effect.Position + velocity:Resized(probeOffset)
        interactWithNearbyBreakableGrids(probePos, gridRadius, vortexData)
    end
    local owner = findPlayerByInitSeed(vortexData.ownerInitSeed)
    interactWithNearbySpecialEntities(probePos, gridRadius, owner or Isaac.GetPlayer(0))
    return isBlockingGridAt(room, probePos)
end

local function applyVortexPull(position, radius, strength)
    local entities = Isaac.GetRoomEntities()
    for _, entity in ipairs(entities) do
        local npc = entity:ToNPC()
        if isDamageableEnemy(npc) then
            local offset = position - npc.Position
            local distance = offset:Length()
            if distance > 0.1 and distance <= radius then
                local pullScale = 1 - (distance / radius)
                if pullScale < 0 then
                    pullScale = 0
                end
                local pullVelocity = offset:Resized((0.6 + 3.4 * pullScale) * strength)
                npc.Velocity = npc.Velocity * 0.45 + pullVelocity
                if EntityFlag and EntityFlag.FLAG_ATTRACTED then
                    npc:AddEntityFlags(EntityFlag.FLAG_ATTRACTED)
                end
            end
        end
    end
end

local function applyVortexTouchDamage(effect, vortexData)
    local owner = findPlayerByInitSeed(vortexData.ownerInitSeed)
    local sourceEntity = owner or Isaac.GetPlayer(0) or effect
    local sourceRef = EntityRef(sourceEntity)
    local now = Game():GetFrameCount()
    local scaleX = 1
    if effect.SpriteScale and effect.SpriteScale.X then
        scaleX = effect.SpriteScale.X
    end
    local touchRadius = (vortexData.touchRadius or 72) * math.max(0.45, scaleX)
    local touchTick = vortexData.touchTick or 1
    local damage = vortexData.touchDamage or 1
    local touchFlags = (DamageFlag and DamageFlag.DAMAGE_IGNORE_ARMOR) or 0

    for _, entity in ipairs(Isaac.GetRoomEntities()) do
        local npc = entity:ToNPC()
        if isDamageableEnemy(npc) then
            if npc.Position:Distance(effect.Position) <= touchRadius then
                local key = npc.InitSeed or npc.Index
                local last = vortexData.touchedAt[key]
                if (not last) or (now - last >= touchTick) then
                    npc:TakeDamage(damage, touchFlags, sourceRef, 0)
                    vortexData.touchedAt[key] = now
                end
            end
        end
    end
end

local function applyFixedExplosionDamage(position, radius, damage, sourceEntity)
    if damage <= 0 then
        return
    end

    local sourceRef = EntityRef(sourceEntity or Isaac.GetPlayer(0))
    local damageFlags = ((DamageFlag and DamageFlag.DAMAGE_EXPLOSION) or 0)
        | ((DamageFlag and DamageFlag.DAMAGE_IGNORE_ARMOR) or 0)

    for _, entity in ipairs(Isaac.GetRoomEntities()) do
        local npc = entity:ToNPC()
        if isDamageableEnemy(npc) and npc.Position:Distance(position) <= radius then
            npc:TakeDamage(damage, damageFlags, sourceRef, 0)
        end
    end
end

local function explodeVortex(effect, vortexData)
    if vortexData.exploded then
        return
    end
    vortexData.exploded = true

    local owner = findPlayerByInitSeed(vortexData.ownerInitSeed)
    local sourceEntity = owner or Isaac.GetPlayer(0) or effect
    local damage = getVortexExplosionDamage(owner or { Damage = 3.5 })
    if (not owner) and vortexData.explosionDamage then
        damage = vortexData.explosionDamage
    end
    local fixedRadius = vortexData.explodeRadius or (ConchBlessing.dragon.data.vortexExplosionRadius or 180)
    local visualDamage = ConchBlessing.dragon.data.vortexExplosionVisualDamage or 0
    local position = effect.Position

    if vortexData.isWhirlpool then
        local particle = findEffectByInitSeed(vortexData.particleInitSeed)
        if particle then
            particle:Remove()
        end

        local splash = Isaac.Spawn(
            EntityType.ENTITY_EFFECT,
            BIG_WATER_SPLASH_VARIANT,
            0,
            position + Vector(0, 10),
            Vector.Zero,
            sourceEntity
        ):ToEffect()
        if splash then
            local splashScale = 0.5 * BIG_WATER_SPLASH_SCALE_MULT
            splash.SpriteScale = Vector(splashScale, splashScale)
            splash.DepthOffset = 28
            safePlayAnimation(splash:GetSprite(), "Poof", true)
        end

        playSfxSet({ SFX_WATER_EXPLODE, SFX_WATER_EXPLODE_ALT }, 1.25, 0.98, 2)
    end

    -- Follow-up explosion should also react to fireplace/TNT around the blast.
    interactWithNearbyBreakableGrids(position, fixedRadius, {
        ownerInitSeed = vortexData.ownerInitSeed,
        gridTouchedAt = {},
        gridInteractionTick = 1,
    })
    interactWithNearbySpecialEntities(position, fixedRadius, sourceEntity)

    applyFixedExplosionDamage(position, fixedRadius, damage, sourceEntity)
    doSoflamStyleExplosion(nil, sourceEntity, position, visualDamage)

    playSfx(SFX_WHIRL_SPAWN_ALT, 0.7, 0.9, 2)
end

ConchBlessing.dragon.onEvaluateCache = function(_, player, cacheFlag)
    if not hasDragon(player) then
        return
    end

    if cacheFlag == CacheFlag.CACHE_FLYING then
        player.CanFly = true
    end

    if cacheFlag == CacheFlag.CACHE_TEARFLAG then
        player.TearFlags = player.TearFlags | TearFlags.TEAR_SPECTRAL
    end
end

ConchBlessing.dragon.onFireTear = function(_, tear)
    if not tear or ConchBlessing.dragon._isInternalSpawn then
        return
    end

    local tData = tear:GetData()
    if tData and tData.__ConchDragonInternal then
        return
    end

    local player = getPlayerFromEntity(tear)
    incrementAttackCount(player)
end

ConchBlessing.dragon.onPostLaserInit = function(_, laser)
    if not laser or ConchBlessing.dragon._isInternalSpawn then
        return
    end

    local lData = laser:GetData()
    if lData and lData.__ConchDragonInternal then
        return
    end

    local player = getPlayerFromEntity(laser)
    incrementAttackCount(player)
end

ConchBlessing.dragon.onPostKnifeInit = function(_, knife)
    if not knife or ConchBlessing.dragon._isInternalSpawn then
        return
    end

    local player = getPlayerFromEntity(knife)
    incrementAttackCount(player)
end

ConchBlessing.dragon.onPostBombInit = function(_, bomb)
    if not bomb or ConchBlessing.dragon._isInternalSpawn then
        return
    end

    local player = getPlayerFromEntity(bomb)
    incrementAttackCount(player)
end

ConchBlessing.dragon.onPostLaserUpdate = function(_, laser)
    if not laser then
        return
    end

    local lData = laser:GetData()
    local techXData = lData and lData.__ConchDragonTechX
    if not techXData then
        return
    end

    techXData.age = (techXData.age or 0) + 1
    local life = techXData.life or 60
    local progress = clamp(techXData.age / life, 0, 1)
    local speedScale = 1 - progress

    if speedScale <= 0 then
        laser:Remove()
        return
    end

    local direction = techXData.direction or Vector(1, 0)
    local initialSpeed = techXData.initialSpeed or 0
    laser.Velocity = direction * (initialSpeed * speedScale)
    laser.Color = TECHX_COLOR
    laser:SetColor(TECHX_COLOR, -1, 1, false, false)
    local updateSprite = laser:GetSprite()
    if updateSprite then
        updateSprite.Color = TECHX_COLOR
    end

    if laser.Velocity:Length() <= 0.05 then
        laser:Remove()
    end
end

ConchBlessing.dragon.onPostEffectUpdate = function(_, effect)
    if not effect then
        return
    end

    local eData = effect:GetData()
    local vortexData = eData and eData.__ConchDragonVortex
    if vortexData then
        vortexData.age = (vortexData.age or 0) + 1
        local life = vortexData.life or 60
        local progress = clamp(vortexData.age / life, 0, 1)
        local speedScale = 1 - progress

        local direction = vortexData.direction or Vector(1, 0)
        local initialSpeed = vortexData.initialSpeed or 0
        effect.Velocity = direction * (initialSpeed * speedScale)
        effect:SetColor(VORTEX_COLOR, 1, 1, false, false)

        local particle = findEffectByInitSeed(vortexData.particleInitSeed)
        if particle then
            particle.Position = effect.Position
            particle.Velocity = Vector.Zero
        end

        applyVortexTouchDamage(effect, vortexData)
        local wallMode = ConchBlessing.dragon.data.vortexWallMode or "pierce"
        local blockedByGrid = handleVortexGridInteraction(effect, vortexData)
        if wallMode == "stick" and blockedByGrid then
            if not vortexData.stickPosition then
                vortexData.stickPosition = Vector(effect.Position.X, effect.Position.Y)
            end
            vortexData.stuckOnWall = true
            vortexData.initialSpeed = 0
            vortexData.direction = Vector.Zero
            effect.Position = vortexData.stickPosition
            effect.Velocity = Vector.Zero
        end

        local shouldStopBySpeed = effect.Velocity:Length() <= 0.05 and not vortexData.stuckOnWall
        if progress >= 1 or shouldStopBySpeed then
            local spawned = spawnWhirlpool(effect.Position, vortexData)
            if not spawned then
                explodeVortex(effect, vortexData)
            end
            effect:Remove()
        end
        return
    end

    local whirlpoolData = eData and eData.__ConchDragonWhirlpool
    if not whirlpoolData then
        return
    end

    whirlpoolData.age = (whirlpoolData.age or 0) + 1
    effect.Velocity = Vector.Zero

    local particle = findEffectByInitSeed(whirlpoolData.particleInitSeed)
    if particle then
        particle.Position = effect.Position
        particle.Velocity = Vector.Zero
    end

    local interval = whirlpoolData.particleSpawnInterval or 15
    local nextAge = whirlpoolData.nextParticleSpawnAge or interval
    local owner = findPlayerByInitSeed(whirlpoolData.ownerInitSeed)
    local spawner = owner or Isaac.GetPlayer(0)
    local particleScaleRef = (effect.SpriteScale and effect.SpriteScale.X) or ((ConchBlessing.dragon.data.vortexScale or 0.6) * WHIRLPOOL_SCALE_MULT)
    while whirlpoolData.age >= nextAge do
        spawnWhirlpoolParticle(effect.Position, spawner, particleScaleRef, interval + 2)
        playSfx(SFX_WHIRLPOOL_LOOP, 0.62, 0.92, 10)
        nextAge = nextAge + interval
    end
    whirlpoolData.nextParticleSpawnAge = nextAge

    local pullRadius = whirlpoolData.pullRadius or 220
    local pullStrength = whirlpoolData.pullStrength or 0.9
    local gridRadius = (whirlpoolData.touchRadius or (ConchBlessing.dragon.data.vortexTouchRadius or 72))
        * math.max(0.45, (effect.SpriteScale and effect.SpriteScale.X) or 1)
        * 0.6
    interactWithNearbyBreakableGrids(effect.Position, gridRadius, whirlpoolData)
    applyVortexPull(effect.Position, pullRadius, pullStrength)
    applyVortexTouchDamage(effect, whirlpoolData)

    if whirlpoolData.age >= (whirlpoolData.life or 60) and not whirlpoolData.exploded then
        explodeVortex(effect, whirlpoolData)
        effect:Remove()
    end
end

ConchBlessing.dragon.onPlayerUpdate = function(_, player)
    if not player then
        return
    end

    local pData = getPlayerData(player)
    if not hasDragon(player) then
        pData.attackCount = 0
        pData.lastAttackFrame = -1
    end
end

ConchBlessing.dragon.onNewRoom = function()
    local numPlayers = Game():GetNumPlayers()
    for i = 0, numPlayers - 1 do
        local player = Isaac.GetPlayer(i)
        if player then
            local pData = getPlayerData(player)
            pData.attackCount = 0
            pData.lastAttackFrame = -1
        end
    end
end

ConchBlessing.dragon.onGameStarted = function()
    ConchBlessing.dragon._isInternalSpawn = false
    ConchBlessing.dragon._sfxCooldown = {}
    local numPlayers = Game():GetNumPlayers()
    for i = 0, numPlayers - 1 do
        local player = Isaac.GetPlayer(i)
        if player then
            local pData = getPlayerData(player)
            pData.attackCount = 0
            pData.lastAttackFrame = -1
        end
    end
end

ConchBlessing.dragon.onBeforeChange = function(upgradePos, pickup, _)
    return ConchBlessing.template.positive.onBeforeChange(upgradePos, pickup, ConchBlessing.dragon.data)
end

ConchBlessing.dragon.onAfterChange = function(upgradePos, pickup, _)
    ConchBlessing.template.positive.onAfterChange(upgradePos, pickup, ConchBlessing.dragon.data)
end

return ConchBlessing.dragon
