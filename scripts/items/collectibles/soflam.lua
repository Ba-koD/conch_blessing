ConchBlessing.soflam = {}

local DamageProvenance = require("scripts.lib.damage_provenance")
DamageProvenance.registerCallbacks(ConchBlessing)

local SOFLAM_ID = Isaac.GetItemIdByName("SOFLAM")
local PROC_KEY = "soflam"
local PROC_ORIGIN = "soflam_missile"
local DEFAULT_TEAR_WEAPON_TYPE = WeaponType and WeaponType.WEAPON_TEARS or nil
local TECHNOLOGY_WEAPON_TYPE = WeaponType and WeaponType.WEAPON_LASER or nil
local WEAPON_CACHE_FLAG = CacheFlag and CacheFlag.CACHE_WEAPON or nil
local MR_MEGA_ID = (CollectibleType and (CollectibleType.COLLECTIBLE_MR_MEGA or CollectibleType.MR_MEGA)) or 106

-- ===================================================================
-- Configuration
-- ===================================================================
ConchBlessing.soflam.data = {
    baseProcPercent     = 10,      -- base 10% chance
    luckProcPerPoint    = 5,       -- +5% per luck point
    bombDamageMultiplier = 10,     -- Base 10x player damage
    mrMegaDamageMultiplier = 2,    -- Mr. Mega synergy: x2 missile damage (=> total 20x)
    mrMegaRadiusMultiplier = 1.5,  -- Mr. Mega synergy: x1.5 explosion radius
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

local function getCollectibleCount(player, collectibleId)
    if not (player and collectibleId and collectibleId > 0 and player.GetCollectibleNum) then
        return 0
    end

    local okCount, count = pcall(function()
        return player:GetCollectibleNum(collectibleId, true)
    end)
    if not okCount then
        okCount, count = pcall(function()
            return player:GetCollectibleNum(collectibleId)
        end)
    end
    if okCount and type(count) == "number" then
        return math.max(0, math.floor(count))
    end

    if player.HasCollectible and player:HasCollectible(collectibleId) then
        return 1
    end
    return 0
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

-- Matches the game's internal explosion-radius buckets.
local function getBombRadiusFromDamage(damage)
    if damage > 175 then
        return 105
    end
    if damage <= 140 then
        return 75
    end
    return 90
end

-- ===================================================================
-- Visual: spawn Epic Fetus-style crosshair target on the enemy
-- ===================================================================
local function spawnTargetCrosshair(position, spawner, inheritedProvenance)
    local target = Isaac.Spawn(
        EntityType.ENTITY_EFFECT,
        EffectVariant.TARGET,   -- 30: the authentic crosshair
        0,
        position,
        Vector.Zero,
        spawner
    ):ToEffect()

    if target then
        DamageProvenance.markTriggeredAttack(target, PROC_KEY, inheritedProvenance, PROC_ORIGIN)
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
local function spawnRocketEffect(position, spawner, inheritedProvenance)
    local rocket = Isaac.Spawn(
        EntityType.ENTITY_EFFECT,
        EffectVariant.ROCKET,   -- 31: the falling rocket effect
        0,
        position,
        Vector.Zero,
        spawner
    ):ToEffect()

    if rocket then
        DamageProvenance.markTriggeredAttack(rocket, PROC_KEY, inheritedProvenance, PROC_ORIGIN)
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
-- Detonation: Epic Fetus-style explosion (base 10x damage, Mr. Mega synergy supported)
-- ===================================================================
local function detonateAtPosition(player, position, inheritedProvenance)
    local damage = (player.Damage or 3.5) * (ConchBlessing.soflam.data.bombDamageMultiplier or 10)
    local game = Game()
    local mrMegaCount = getCollectibleCount(player, MR_MEGA_ID)
    if mrMegaCount > 0 then
        damage = damage * ((ConchBlessing.soflam.data.mrMegaDamageMultiplier or 2) ^ mrMegaCount)
    end
    local bombFlags = BitSet128 and BitSet128(0, 0) or 0
    if player and player.GetBombFlags then
        local okBombFlags, flags = pcall(function()
            return player:GetBombFlags(true)
        end)
        if not okBombFlags then
            okBombFlags, flags = pcall(function()
                return player:GetBombFlags()
            end)
        end
        if okBombFlags and flags ~= nil then
            bombFlags = flags
        end
    elseif player and player.TearFlags ~= nil then
        bombFlags = player.TearFlags
    end
    if type(bombFlags) == "number" and BitSet128 then
        bombFlags = BitSet128(bombFlags, 0)
    end

    local bombVariant = 0
    if player and player.GetBombVariant then
        local okVariant, variant = pcall(function()
            return player:GetBombVariant(bombFlags, false)
        end)
        if okVariant and type(variant) == "number" then
            bombVariant = variant
        end
    end

    local bomb = Isaac.Spawn(
        EntityType.ENTITY_BOMB,
        bombVariant,
        0,
        position,
        Vector.Zero,
        player
    ):ToBomb()

    if bomb then
        DamageProvenance.markTriggeredAttack(bomb, PROC_KEY, inheritedProvenance, PROC_ORIGIN)

        local okSetFlags = pcall(function()
            bomb.Flags = bombFlags
        end)
        if not okSetFlags then
            -- Keep default flags if the runtime rejects custom flag assignment.
        end

        -- Snapshot natural bomb range after variant/flags are applied.
        local naturalDamage = bomb.ExplosionDamage or 100
        local naturalRadiusMultiplier = bomb.RadiusMultiplier or 1
        local naturalRadius = getBombRadiusFromDamage(naturalDamage) * naturalRadiusMultiplier
        if mrMegaCount > 0 then
            naturalRadius = naturalRadius * (ConchBlessing.soflam.data.mrMegaRadiusMultiplier or 1.5)
        end

        bomb.ExplosionDamage = damage

        local customRadius = getBombRadiusFromDamage(damage)
        if customRadius > 0 then
            bomb.RadiusMultiplier = naturalRadius / customRadius
        end

        bomb.IsFetus = true
        if bomb.SetExplosionCountdown then
            bomb:SetExplosionCountdown(0)
        else
            local customScale = 1
            if customRadius > 0 then
                customScale = naturalRadius / customRadius
            end
            DamageProvenance.withTriggeredSource(player, PROC_KEY, inheritedProvenance, PROC_ORIGIN, function()
                game:BombExplosionEffects(
                    position,
                    damage,
                    bombFlags,
                    Color.Default,
                    player,
                    customScale,
                    true,
                    true,
                    DamageFlag.DAMAGE_EXPLOSION
                )
            end)
            bomb:Remove()
        end
    else
        -- Fallback to manual explosion if spawning a bomb fails.
        DamageProvenance.withTriggeredSource(player, PROC_KEY, inheritedProvenance, PROC_ORIGIN, function()
            game:BombExplosionEffects(
                position,
                damage,
                bombFlags,
                Color.Default,
                player,
                1,
                true,
                true,
                DamageFlag.DAMAGE_EXPLOSION
            )
        end)
    end

    -- Add extra screen shake for impact.
    game:ShakeScreen(4)
end

-- ===================================================================
-- Queue a new lock-on strike against an enemy
-- ===================================================================
local function queueStrike(player, npc, inheritedProvenance)
    if not (player and npc) then return end

    local position = Vector(npc.Position.X, npc.Position.Y)
    local roomIndex = Game():GetLevel():GetCurrentRoomIndex()
    local rocketCount = getRocketCountFromMultishot(player)

    -- Spawn the target crosshair for 2 seconds
    local crosshair = spawnTargetCrosshair(position, player, inheritedProvenance)
    
    local sfx = SFXManager()
    sfx:Play(SoundEffect.SOUND_BIRD_FLAP, 0.6, 0, false, 1.5)

    table.insert(ConchBlessing.soflam._pendingStrikes, {
        phase             = "lockon",
        playerInitSeed    = player.InitSeed,
        npcInitSeed       = npc.InitSeed,
        npcEntity         = npc,
        roomIndex         = roomIndex,
        countdown         = ConchBlessing.soflam.data.lockOnDelayFrames or 120,
        lastKnownPosition = position,
        crosshairEffect   = crosshair,
        rocketEffect      = nil,
        remainingRockets  = rocketCount,
        inheritedProvenance = inheritedProvenance,
    })
end

local function startRocketFall(strike, player)
    strike.phase = "rocket"
    strike.countdown = ConchBlessing.soflam.data.rocketTravelFrames or 15
    strike.rocketEffect = spawnRocketEffect(strike.lastKnownPosition, player, strike.inheritedProvenance)
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

local function enableTechnologyWeapon(player)
    local repentogon = rawget(_G, "REPENTOGON")
    if type(repentogon) ~= "table" or repentogon.Real ~= true then
        return false
    end
    if not player
        or type(player.EnableWeaponType) ~= "function"
        or type(DEFAULT_TEAR_WEAPON_TYPE) ~= "number"
        or type(TECHNOLOGY_WEAPON_TYPE) ~= "number"
    then
        return false
    end

    -- Replace the default tear weapon during this cache rebuild, just like a
    -- Technology-style primary weapon. Removal performs a fresh weapon-cache
    -- rebuild, so never issue a separate cleanup-time false call.
    player:EnableWeaponType(DEFAULT_TEAR_WEAPON_TYPE, false)
    player:EnableWeaponType(TECHNOLOGY_WEAPON_TYPE, true)
    return true
end

ConchBlessing.soflam.onEvaluateCache = function(_, player, cacheFlag)
    if WEAPON_CACHE_FLAG == nil or cacheFlag ~= WEAPON_CACHE_FLAG then
        return
    end
    if player and player:HasCollectible(SOFLAM_ID) then
        enableTechnologyWeapon(player)
    end
end

local function tryProcFromAttack(player, attackEntity, npc, inheritedProvenance)
    if not (player and attackEntity and npc and player:HasCollectible(SOFLAM_ID)) then return end

    -- One physical attack gets exactly one SOFLAM roll. Claim before RNG so a
    -- failed Tech X/Brimstone/piercing hit cannot reroll on later damage ticks.
    if not DamageProvenance.tryClaimAttackProc(attackEntity, PROC_KEY) then return end

    -- Consume one deterministic item-owned roll for this attack instance.
    local chance = getProcChance(player)
    if chance <= 0 then return end

    local rng = player:GetCollectibleRNG(SOFLAM_ID)
    if rng:RandomFloat() <= chance then
        queueStrike(player, npc, inheritedProvenance)
    end
end

--- REPENTOGON path: roll only after eligible player-owned attack damage was applied.
ConchBlessing.soflam.onPostEntityTakeDamage = function(_, entity, amount, _flags, source, _countdown, extraSource)
    if not entity or (tonumber(amount) or 0) <= 0 then return end

    local npc = entity:ToNPC()
    if not (npc and npc:Exists() and npc:IsVulnerableEnemy()) then
        return
    end
    if npc:HasEntityFlags(EntityFlag.FLAG_FRIENDLY) then
        return
    end

    local attackEntity, player, provenance = DamageProvenance.getEligiblePlayerAttack(source, extraSource, PROC_KEY)
    if not (attackEntity and player) then return end

    tryProcFromAttack(player, attackEntity, npc, provenance)
end

--- Base-game fallback: collision is weaker than confirmed damage, so disable it when
--- the applied-damage callback is available and reject lineages that already ran SOFLAM.
ConchBlessing.soflam.onTearCollision = function(_, tear, collider, _low)
    if DamageProvenance.hasAppliedDamageCallback() then return nil end
    if not (tear and DamageProvenance.isHitProcEligible(tear, PROC_KEY)) then return nil end

    local npc = collider and collider:ToNPC() or nil
    if not (npc and npc:Exists() and npc:IsVulnerableEnemy()) then return nil end
    if npc:HasEntityFlags(EntityFlag.FLAG_FRIENDLY) then return nil end

    local player = DamageProvenance.getPlayerOwner(tear)
    local provenance = DamageProvenance.getSnapshot(tear)
    tryProcFromAttack(player, tear, npc, provenance)
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
        local npc = strike.npcEntity
        if npc
            and npc:Exists()
            and not npc:IsDead()
            and (not strike.npcInitSeed or npc.InitSeed == strike.npcInitSeed)
        then
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
                detonateAtPosition(player, strike.lastKnownPosition, strike.inheritedProvenance)
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
            detonateAtPosition(player, strike.lastKnownPosition, strike.inheritedProvenance)
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
    local numPlayers = Game():GetNumPlayers()
    for i = 0, numPlayers - 1 do
        local player = Isaac.GetPlayer(i)
        if player and player:HasCollectible(SOFLAM_ID) then
            if WEAPON_CACHE_FLAG ~= nil then
                player:AddCacheFlags(WEAPON_CACHE_FLAG)
                player:EvaluateItems()
            end
        end
    end
end

return ConchBlessing.soflam
