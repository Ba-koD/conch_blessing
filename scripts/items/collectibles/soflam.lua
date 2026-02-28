ConchBlessing.soflam = {}

local SOFLAM_ID = Isaac.GetItemIdByName("SOFLAM")

-- ===================================================================
-- Configuration
-- ===================================================================
ConchBlessing.soflam.data = {
    baseProcPercent     = 10,      -- base 10% chance
    luckProcPerPoint    = 5,       -- +5% per luck point
    bombDamageMultiplier = 10,     -- 10x player damage
    lockOnDelayFrames   = 45,     -- 1.5 seconds lock-on phase
    rocketTravelFrames  = 0,      -- Fallback max frames for rocket fall
    rocketCount         = 1,      -- Rockets dropped per strike
    rocketIntervalFrames = 2,     -- Delay between rockets in the same strike
}

-- Active strikes list (persists across frames within a room)
ConchBlessing.soflam._pendingStrikes = ConchBlessing.soflam._pendingStrikes or {}

-- ===================================================================
-- Utility helpers
-- ===================================================================
local function clamp(value, minVal, maxVal)
    if value < minVal then return minVal end
    if value > maxVal then return maxVal end
    return value
end

local function getPlayerFromTear(tear)
    if not tear then return nil end
    local spawner = tear.SpawnerEntity
    if spawner and spawner:ToPlayer() then
        return spawner:ToPlayer()
    end
    local parent = tear.Parent
    if parent and parent:ToPlayer() then
        return parent:ToPlayer()
    end
    return nil
end

--- Calculate proc chance: base 10% + luck * 5%, capped [0, 100]
local function getProcChance(player)
    local luck = (player and player.Luck) or 0
    local data = ConchBlessing.soflam.data
    local chancePercent = data.baseProcPercent + luck * data.luckProcPerPoint
    return clamp(chancePercent, 0, 100) / 100
end

-- Rocket count follows current multishot tear count when available.
local function getRocketCountFromMultishot(player)
    local baseCount = ConchBlessing.soflam.data.rocketCount or 1
    if not (player and player.GetMultiShotParams) then
        return baseCount
    end

    local weaponType = 1
    if player.GetWeaponType then
        local okWeaponType, currentWeaponType = pcall(function()
            return player:GetWeaponType()
        end)
        if okWeaponType and type(currentWeaponType) == "number" then
            weaponType = currentWeaponType
        end
    end

    local okParams, multiParams = pcall(function()
        return player:GetMultiShotParams(weaponType)
    end)
    if not (okParams and multiParams and multiParams.GetNumTears) then
        return baseCount
    end

    local okNumTears, numTears = pcall(function()
        return multiParams:GetNumTears()
    end)
    if not okNumTears or type(numTears) ~= "number" then
        return baseCount
    end

    return math.max(1, math.floor(numTears + 0.5))
end

local function findPlayerByInitSeed(initSeed)
    if not initSeed then return nil end
    local n = Game():GetNumPlayers()
    for i = 0, n - 1 do
        local p = Isaac.GetPlayer(i)
        if p and p.InitSeed == initSeed then
            return p
        end
    end
    return nil
end

local function findNpcByInitSeed(initSeed)
    if not initSeed then return nil end
    for _, entity in ipairs(Isaac.GetRoomEntities()) do
        local npc = entity:ToNPC()
        if npc and npc.InitSeed == initSeed and npc:Exists() then
            return npc
        end
    end
    return nil
end

local function findPendingStrike(playerInitSeed, npcInitSeed, roomIndex)
    for _, strike in ipairs(ConchBlessing.soflam._pendingStrikes) do
        if strike.playerInitSeed == playerInitSeed
            and strike.npcInitSeed == npcInitSeed
            and strike.roomIndex == roomIndex then
            return strike
        end
    end
    return nil
end

-- ===================================================================
-- Visual: spawn Epic Fetus-style crosshair target on the enemy
-- ===================================================================
local function spawnTargetCrosshair(position, spawner)
    local target = Isaac.Spawn(
        EntityType.ENTITY_EFFECT,
        EffectVariant.TARGET,   -- 30: the authentic crosshair
        0,
        position,
        Vector.Zero,
        spawner
    ):ToEffect()

    if target then
        target.DepthOffset = 100
        -- Ensure it stays alive long enough for our lock-on phase
        local timeout = (ConchBlessing.soflam.data.lockOnDelayFrames or 45) + 10
        target.Timeout = timeout
        if target.SetTimeout then
            target:SetTimeout(timeout)
        end
    end
    return target
end

-- ===================================================================
-- Visual: spawn Epic Fetus-style rocket falling from the sky
-- ===================================================================
local function spawnRocketEffect(position, spawner)
    local rocket = Isaac.Spawn(
        EntityType.ENTITY_EFFECT,
        EffectVariant.ROCKET,   -- 31: the falling rocket effect
        0,
        position,
        Vector.Zero,
        spawner
    ):ToEffect()

    if rocket then
        rocket.DepthOffset = 200
        local timeout = (ConchBlessing.soflam.data.rocketTravelFrames or 20) + 5
        rocket.Timeout = timeout
        if rocket.SetTimeout then
            rocket:SetTimeout(timeout)
        end
    end
    return rocket
end

-- ===================================================================
-- Detonation: Epic Fetus-style explosion dealing 10x damage
-- ===================================================================
local function detonateAtPosition(player, position)
    local damage = (player.Damage or 3.5) * (ConchBlessing.soflam.data.bombDamageMultiplier or 10)
    local game = Game()
    local tearFlags = (player and player.TearFlags) or TearFlags.TEAR_NORMAL
    if tearFlags == 0 then
        tearFlags = TearFlags.TEAR_NORMAL
    end

    -- Vanilla-like full bomb package (damage + VFX + tearflag effects).
    -- DamageSource=true allows self damage while still respecting explosion immunity.
    game:BombExplosionEffects(
        position,
        damage,
        tearFlags,
        Color.Default,
        player,
        1,
        true,
        true,
        DamageFlag.DAMAGE_EXPLOSION
    )

    -- Add extra screen shake for impact.
    game:ShakeScreen(4)
end

-- ===================================================================
-- Queue a new lock-on strike against an enemy
-- ===================================================================
local function queueStrike(player, npc)
    if not (player and npc) then return end

    local position = Vector(npc.Position.X, npc.Position.Y)
    local roomIndex = Game():GetLevel():GetCurrentRoomIndex()
    local rocketCount = getRocketCountFromMultishot(player)

    -- Prevent duplicate queued strikes from multishot tears on the same target.
    local existingStrike = findPendingStrike(player.InitSeed, npc.InitSeed, roomIndex)
    if existingStrike then
        -- Keep the larger value in case multishot changed before impact.
        existingStrike.remainingRockets = math.max(existingStrike.remainingRockets or 1, rocketCount)
        return
    end

    -- Spawn the target crosshair for 2 seconds
    local crosshair = spawnTargetCrosshair(position, player)
    
    local sfx = SFXManager()
    sfx:Play(SoundEffect.SOUND_BIRD_FLAP, 0.6, 0, false, 1.5)

    table.insert(ConchBlessing.soflam._pendingStrikes, {
        phase             = "lockon",
        playerInitSeed    = player.InitSeed,
        npcInitSeed       = npc.InitSeed,
        roomIndex         = roomIndex,
        countdown         = ConchBlessing.soflam.data.lockOnDelayFrames or 120,
        lastKnownPosition = position,
        crosshairEffect   = crosshair,
        rocketEffect      = nil,
        remainingRockets  = rocketCount,
    })
end

local function startRocketFall(strike, player)
    strike.phase = "rocket"
    strike.countdown = ConchBlessing.soflam.data.rocketTravelFrames or 15
    strike.rocketEffect = spawnRocketEffect(strike.lastKnownPosition, player)
end

-- ===================================================================
-- Cleanup helpers
-- ===================================================================
local function removeStrikeEffects(strike)
    if strike.crosshairEffect and strike.crosshairEffect:Exists() then
        strike.crosshairEffect:Remove()
    end
    if strike.rocketEffect and strike.rocketEffect:Exists() then
        strike.rocketEffect:Remove()
    end
end

local function clearPendingStrikes()
    local strikes = ConchBlessing.soflam._pendingStrikes
    for i = #strikes, 1, -1 do
        removeStrikeEffects(strikes[i])
        strikes[i] = nil
    end
end

-- ===================================================================
-- Callbacks
-- ===================================================================

ConchBlessing.soflam.onPickup = function(_, player, _, _)
    if not player then return end
    player:AddCacheFlags(CacheFlag.CACHE_TEARFLAG)
    player:EvaluateItems()
end

ConchBlessing.soflam.onEvaluateCache = function(_, player, cacheFlag)
    if cacheFlag ~= CacheFlag.CACHE_TEARFLAG then
        return
    end
    if player and player:HasCollectible(SOFLAM_ID) then
        player.TearFlags = player.TearFlags | TearFlags.TEAR_PIERCING
    end
end

--- On tear hitting an enemy: roll for lock-on
ConchBlessing.soflam.onTearCollision = function(_, tear, collider, _)
    if not (tear and collider) then return nil end

    local player = getPlayerFromTear(tear)
    if not (player and player:HasCollectible(SOFLAM_ID)) then
        return nil
    end

    local npc = collider:ToNPC()
    if not (npc and npc:Exists() and npc:IsVulnerableEnemy() and not npc:IsDead()) then
        return nil
    end
    if npc:HasEntityFlags(EntityFlag.FLAG_FRIENDLY) then
        return nil
    end

    -- Prevent duplicate proc from the same tear on the same enemy
    local tearData = tear:GetData()
    tearData.__ConchSoflamHit = tearData.__ConchSoflamHit or {}
    local npcKey = npc.InitSeed or npc.Index
    if tearData.__ConchSoflamHit[npcKey] then
        return nil
    end
    tearData.__ConchSoflamHit[npcKey] = true

    -- Roll proc chance
    local chance = getProcChance(player)
    if chance <= 0 then return nil end

    local rng = RNG()
    local seed = (tear.InitSeed or player.InitSeed or 0) + (npc.InitSeed or npc.Index or 0)
    rng:SetSeed(seed, 35)

    if rng:RandomFloat() <= chance then
        queueStrike(player, npc)
    end

    return nil
end

--- Main update: tick pending strikes
ConchBlessing.soflam.onUpdate = function(_)
    local strikes = ConchBlessing.soflam._pendingStrikes
    if #strikes == 0 then return end

    local roomIndex = Game():GetLevel():GetCurrentRoomIndex()

    for i = #strikes, 1, -1 do
        local strike = strikes[i]

        -- Remove if room changed
        if strike.roomIndex ~= roomIndex then
            removeStrikeEffects(strike)
            table.remove(strikes, i)
            goto continue
        end

        -- Remove if player no longer has the item
        local player = findPlayerByInitSeed(strike.playerInitSeed)
        if not (player and player:HasCollectible(SOFLAM_ID)) then
            removeStrikeEffects(strike)
            table.remove(strikes, i)
            goto continue
        end

        -- Track enemy position if still alive
        local npc = findNpcByInitSeed(strike.npcInitSeed)
        if npc and npc:Exists() and not npc:IsDead() then
            strike.lastKnownPosition = Vector(npc.Position.X, npc.Position.Y)
        end

        -- Keep crosshair synced to target
        if strike.crosshairEffect and strike.crosshairEffect:Exists() then
            strike.crosshairEffect.Position = strike.lastKnownPosition
        end

        -- Keep rocket synced to target position during fall
        if strike.phase == "rocket" and strike.rocketEffect and strike.rocketEffect:Exists() then
            strike.rocketEffect.Position = strike.lastKnownPosition
            local sprite = strike.rocketEffect:GetSprite()

            -- Check if rocket visually hit the floor perfectly (usually frame 14 or finishing "Fall")
            if (strike.countdown or 0) <= 0 or sprite:IsFinished("Fall") or sprite:GetFrame() >= 14 then
                -- Remove the effect before manual detonation to prevent duplicate native ROCKET impact.
                strike.rocketEffect:Remove()
                strike.rocketEffect = nil
                detonateAtPosition(player, strike.lastKnownPosition)
                strike.remainingRockets = (strike.remainingRockets or 1) - 1
                if strike.remainingRockets > 0 then
                    strike.phase = "rocket_interval"
                    strike.countdown = ConchBlessing.soflam.data.rocketIntervalFrames or 2
                else
                    table.remove(strikes, i)
                end
                goto continue
            end
        elseif strike.phase == "rocket" then
            -- Failsafe: if the effect was removed by the game engine, trigger explosion
            detonateAtPosition(player, strike.lastKnownPosition)
            strike.remainingRockets = (strike.remainingRockets or 1) - 1
            if strike.remainingRockets > 0 then
                strike.phase = "rocket_interval"
                strike.countdown = ConchBlessing.soflam.data.rocketIntervalFrames or 2
            else
                table.remove(strikes, i)
            end
            goto continue
        end

        -- Tick countdown
        strike.countdown = (strike.countdown or 0) - 1

        if strike.countdown <= 0 then
            if strike.phase == "lockon" then
                -- Transition: crosshair -> rocket falling
                if strike.crosshairEffect and strike.crosshairEffect:Exists() then
                    strike.crosshairEffect:Remove()
                end
                strike.crosshairEffect = nil

                startRocketFall(strike, player)
            elseif strike.phase == "rocket_interval" then
                startRocketFall(strike, player)
            end
        end

        ::continue::
    end
end

--- Room change: clear all pending strikes
ConchBlessing.soflam.onNewRoom = function(_)
    clearPendingStrikes()
end

--- Game start: clear state
ConchBlessing.soflam.onGameStarted = function(_)
    clearPendingStrikes()
end

return ConchBlessing.soflam
