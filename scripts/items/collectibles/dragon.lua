ConchBlessing.dragon = {}

local DRAGON_ID = Isaac.GetItemIdByName("Dragon")
local VORTEX_VARIANT = (EffectVariant and EffectVariant.BRIMSTONE_BALL) or 113

ConchBlessing.dragon.data = {
    attacksPerTrigger = 5,
    spawnCount = 5, -- fixed count (no stack scaling)
    projectileSpeed = 6.3, -- 70% speed baseline
    decelerationFrames = 60, -- fully stops in 60 ticks
    baseDamagePercent = 0.05, -- 5% of player damage
    synergyDamageBonus = 0.05, -- +5% per extra stack for vortex touch damage
    vortexExplosionDamageMultiplier = 20, -- SOFLAM-like explosion damage
    techXRadius = 24,
    vortexPullRadius = 220,
    vortexPullStrength = 3.2,
    vortexExplosionRadius = 180, -- fixed explosion radius reference
    vortexExplosionVisualDamage = 0, -- visual-only explode damage
    vortexTouchRadius = 72, -- base radius at SpriteScale 1.0
    vortexTouchTick = 1,
    vortexScale = 0.6,
}

ConchBlessing.dragon._isInternalSpawn = false

-- Tech X ring texture is red-heavy, so use additive offsets to force a yellow tint.
local TECHX_COLOR = Color(1.0, 1.0, 1.0, 1.0, 0.55, 1.75, -0.05)
local VORTEX_COLOR = Color(1.0, 1.0, 1.0, 1.0, -0.75, 0.45, 1.25)

local function clamp(value, minValue, maxValue)
    if value < minValue then return minValue end
    if value > maxValue then return maxValue end
    return value
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
    return (player.Damage or 3.5) * (ConchBlessing.dragon.data.baseDamagePercent or 0.05)
end

local function getVortexTouchDamage(player, dragonCount)
    local playerDamage = player.Damage or 3.5
    local basePercent = ConchBlessing.dragon.data.baseDamagePercent or 0.05
    local perExtra = ConchBlessing.dragon.data.synergyDamageBonus or 0.05
    local extraStacks = math.max(0, dragonCount - 1)
    local totalPercent = basePercent + (perExtra * extraStacks)
    local out = playerDamage * totalPercent
    if out < 1 then
        out = 1
    end
    return out
end

local function getVortexExplosionDamage(player)
    local mult = ConchBlessing.dragon.data.vortexExplosionDamageMultiplier or 20
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

    effect.SpriteScale = Vector(ConchBlessing.dragon.data.vortexScale or 0.6, ConchBlessing.dragon.data.vortexScale or 0.6)
    effect:SetColor(VORTEX_COLOR, -1, 1, false, false)
    effect.DepthOffset = 25

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
        touchedAt = {},
        exploded = false,
    }
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
    local damage = vortexData.explosionDamage
        or getVortexExplosionDamage(owner or { Damage = 3.5 })
    local fixedRadius = vortexData.explodeRadius or (ConchBlessing.dragon.data.vortexExplosionRadius or 180)
    local visualDamage = ConchBlessing.dragon.data.vortexExplosionVisualDamage or 0

    applyFixedExplosionDamage(effect.Position, fixedRadius, damage, sourceEntity)
    doSoflamStyleExplosion(nil, sourceEntity, effect.Position, visualDamage)

    local explosionSfx = SoundEffect
        and (SoundEffect.SOUND_EXPLOSION_WEAK or SoundEffect.SOUND_ROCKET_BLAST_1 or SoundEffect.SOUND_BOSS1_EXPLOSIONS)
    if explosionSfx then
        SFXManager():Play(explosionSfx, 0.7, 0, false, 1.0)
    end
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
    if not vortexData then
        return
    end

    vortexData.age = (vortexData.age or 0) + 1
    local life = vortexData.life or 60
    local progress = clamp(vortexData.age / life, 0, 1)
    local speedScale = 1 - progress

    local direction = vortexData.direction or Vector(1, 0)
    local initialSpeed = vortexData.initialSpeed or 0
    effect.Velocity = direction * (initialSpeed * speedScale)
    effect:SetColor(VORTEX_COLOR, 1, 1, false, false)

    local pullRadius = vortexData.pullRadius or 90
    local pullStrength = (vortexData.pullStrength or 0.9) * (0.5 + 0.5 * speedScale)
    applyVortexPull(effect.Position, pullRadius, pullStrength)
    applyVortexTouchDamage(effect, vortexData)

    if (progress >= 1 or effect.Velocity:Length() <= 0.05) and not vortexData.exploded then
        explodeVortex(effect, vortexData)
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
    end
end

ConchBlessing.dragon.onNewRoom = function()
    local numPlayers = Game():GetNumPlayers()
    for i = 0, numPlayers - 1 do
        local player = Isaac.GetPlayer(i)
        if player then
            local pData = getPlayerData(player)
            pData.attackCount = 0
        end
    end
end

ConchBlessing.dragon.onGameStarted = function()
    ConchBlessing.dragon._isInternalSpawn = false
    local numPlayers = Game():GetNumPlayers()
    for i = 0, numPlayers - 1 do
        local player = Isaac.GetPlayer(i)
        if player then
            local pData = getPlayerData(player)
            pData.attackCount = 0
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
