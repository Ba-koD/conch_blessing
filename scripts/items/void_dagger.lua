ConchBlessing.voiddagger = {}

-- Tunable parameters similar to live_eye style
ConchBlessing.voiddagger.data = {
    -- p(S) = lerp(pMax ↘ pMin, t),  t = clamp((S - sMin) / (sMax - sMin), 0, 1)
    -- S=sMin → pMax, S=sMax → pMin. Default: sMin=2.73→pMax=0.20, sMax=120→pMin=0.01
    sMin = 2,   -- low S = start point
    sMax = 120.0,  -- high S = end point
    pMin = 0.01,   -- min p = 1%
    pMax = 0.25,   -- max p = 25%
    targetLockoutF = 20, -- frames per-target lockout
    Radius = 15,
}

local VOID_DAGGER_ID = Isaac.GetItemIdByName("Void Dagger")

-- runtime guard map to avoid multi-trigger spam on the same enemy within a short window
ConchBlessing.voiddagger._lastProcFrameByNpc = {}
ConchBlessing.voiddagger._lastGlobalSpawnFrame = -999
ConchBlessing.voiddagger._upgradeAnim = nil

-- S ≈ 30 / (MaxFireDelay + 1)
local function getShotsPerSecond(player)
    local maxDelay = player.MaxFireDelay or 0
    return math.max(1.0, 30.0 / (maxDelay + 1.0))
end

-- R = TearRange / 40
local function getDisplayRange(player)
    local tr = player.TearRange
    return tr / 40.0
end

local function computeRingRadiusFromRange(player)
    return ConchBlessing.voiddagger.data.Radius
end

-- Timeout = 10, 20, 30, 40, 50, 60 frames by damage buckets [0~10), [10~20) ... [50~∞)
local function computeTimeoutFromDamage(damage)
    local dmg = tonumber(damage) or 0
    if dmg < 0 then dmg = 0 end
    local bucket = math.floor(dmg / 10) + 1 -- 0~9→1, 10~19→2, ...
    local timeout = 10 * bucket
    if timeout > 60 then timeout = 60 end
    if timeout < 10 then timeout = 10 end
    return timeout
end

-- p(S) = lerp(pMax..pMin, t), t = clamp((S - sMin)/(sMax - sMin), 0, 1)
local function computeProcChanceFromS(shotsPerSecond)
    local cfg = ConchBlessing.voiddagger.data
    local s = math.max(0.001, shotsPerSecond)
    local sMin, sMax = cfg.sMin, cfg.sMax
    local pMin, pMax = cfg.pMin, cfg.pMax
    local span = math.max(0.001, sMax - sMin)
    local t = (s - sMin) / span
    if t < 0 then t = 0 end
    if t > 1 then t = 1 end
    -- p(S) = lerp(pMax..pMin, t), t = clamp((S - sMin)/(sMax - sMin), 0, 1)
    local p = pMax + (pMin - pMax) * t
    if p < pMin then p = pMin end
    if p > pMax then p = pMax end
    return p
end

-- Luck bonus: pFinal = pBase × (1 + 0.1 × clamp(luck, 0, 10))
-- 0Luck → +0%, 10Luck → +100% (max 2x). Cap at 100%
local function applyLuckBonus(p, luck)
    local L = math.max(0.0, math.min(10.0, luck or 0.0))
    local factor = 1.0 + 0.1 * L
    local out = p * factor
    if out > 1.0 then out = 1.0 end
    return out, factor, L
end

local function shouldProcForNpc(npc)
    if not npc then return false end
    local now = Game():GetFrameCount()
    local last = ConchBlessing.voiddagger._lastProcFrameByNpc[npc.InitSeed or npc.Index]
    local lockF = ConchBlessing.voiddagger.data.targetLockoutF or 20
    if last and now - last < lockF then -- per-target lockout
        return false
    end
    ConchBlessing.voiddagger._lastProcFrameByNpc[npc.InitSeed or npc.Index] = now
    return true
end

-- Upgrade visual (Neutral): brief gray pulse before, soft poof after
ConchBlessing.voiddagger.onBeforeChange = function(upgradePos, pickup, _)
    ConchBlessing.voiddagger._upgradeAnim = {
        pickup = pickup,
        pos = upgradePos,
        frames = 30,
        phase = "before",
        maxAdd = 0.6,
        soundId = SoundEffect.SOUND_POWERUP_SPEWER,
    }
    local sfx = SFXManager()
    sfx:Stop(SoundEffect.SOUND_POWERUP_SPEWER)
    sfx:Play(SoundEffect.SOUND_POWERUP_SPEWER, 0.2, 0, true, 1.0, 0)
    return 30
end

ConchBlessing.voiddagger.onAfterChange = function(upgradePos, pickup, _)
    Isaac.Spawn(EntityType.ENTITY_EFFECT, EffectVariant.POOF01, 0, upgradePos, Vector.Zero, nil)
    ConchBlessing.voiddagger._upgradeAnim = {
        pickup = pickup,
        pos = upgradePos,
        frames = 30,
        phase = "after",
        maxAdd = 0.6,
        soundId = SoundEffect.SOUND_POWERUP_SPEWER,
    }
    local spr = pickup and pickup:GetSprite() or nil
    if spr then
        spr.Color = Color(1, 1, 1, 1, 0.6, 0.6, 0.6)
    end
end

-- Spawn a Maw of Void ring at position with fixed lifetime and no black heart drops
local function spawnVoidRingAt(player, pos)
    -- Per request: use EntityPlayer:SpawnMawOfVoid
    -- First parameter is numeric (angle or mode). Use 0 and pin the laser at impact.
    local ring = player:SpawnMawOfVoid(0)
    if not ring then return end
    local laser = ring:ToLaser()
    if not laser then return end

    -- Set Timeout based on player's damage
    local timeoutF = computeTimeoutFromDamage(player.Damage)
    if laser.SetTimeout then laser:SetTimeout(timeoutF) end
    laser.Timeout = timeoutF

    -- No black heart drops from the ring
    if laser.SetBlackHpDropChance then
        laser:SetBlackHpDropChance(0)
    elseif laser.BlackHpDropChance ~= nil then
        laser.BlackHpDropChance = 0
    end

    -- Detach from following player and lock at hit position
    laser.DisableFollowParent = true
    laser.Position = pos
    laser.ParentOffset = pos - player.Position
    laser.Velocity = Vector.Zero

    -- Radius scales with player's range
    local radius = computeRingRadiusFromRange(player)
    if laser.Radius ~= nil then
        laser.Radius = radius
    end
end

-- Handle tear collision to trigger ring on hit
ConchBlessing.voiddagger.onTearCollision = function(_, tear, collider, _)
    if not (tear and collider) then return nil end
    local parent = tear.Parent
    if not (parent and parent:ToPlayer()) then return nil end

    local player = parent:ToPlayer()
    if not (player and VOID_DAGGER_ID ~= -1 and player:HasCollectible(VOID_DAGGER_ID)) then
        return nil
    end

    local npc = collider:ToNPC()
    if not (npc and npc:Exists() and npc:IsVulnerableEnemy() and not npc:HasEntityFlags(EntityFlag.FLAG_FRIENDLY)) then
        return nil
    end

    -- Per-target brief lockout to avoid multi-proc spam on multi-hit frames
    if not shouldProcForNpc(npc) then
        return nil
    end

    -- Compute chance scaled inversely with tears
    local shotsPerSecond = getShotsPerSecond(player)          -- S ≈ 30/(MaxFireDelay+1)
    local pBase = computeProcChanceFromS(shotsPerSecond)      -- base chance p(S)
    local p, factor, L = applyLuckBonus(pBase, player.Luck)   -- apply luck bonus
    local R = getDisplayRange(player)                         -- R = TearRange/40
    local dbgRadius = computeRingRadiusFromRange(player)      -- Radius
    local D = player.MaxFireDelay or 0                        -- current MaxFireDelay(frames)
    -- Deterministic RNG per-tear
    local rng = RNG()
    rng:SetSeed(tear.InitSeed or player.InitSeed, 35)
    local roll = rng:RandomFloat()
    if roll < p then
        local hitPos = collider.Position
        spawnVoidRingAt(player, hitPos)
        if ConchBlessing and ConchBlessing.printDebug then
            ConchBlessing.printDebug(string.format(
                "VoidDagger PROC: pBase=%.2f%% pFinal=%.2f%% (x%.1f @Luck=%.1f) roll=%.3f S=%.2f D=%.2f R=%.2f radius=%.2f pos=(%.1f,%.1f) npcSeed=%s",
                pBase * 100.0, p * 100.0, factor, L, roll, shotsPerSecond, D, R, dbgRadius, hitPos.X, hitPos.Y, tostring(npc.InitSeed or npc.Index)
            ))
        end
    end

    return nil
end

-- Optional cleanup each room to keep map light
ConchBlessing.voiddagger.onUpdate = function(_)
    -- Occasionally prune old entries
    if Game():GetFrameCount() % 90 == 0 then
        ConchBlessing.voiddagger._lastProcFrameByNpc = {}
    end

    -- Drive upgrade gray pulse animation
    local anim = ConchBlessing.voiddagger._upgradeAnim
    if anim and anim.frames and anim.frames > 0 and anim.pickup and anim.pickup:Exists() then
        anim.frames = anim.frames - 1
        local total = 30.0
        local t = 1.0 - (anim.frames / total)
        local spr = anim.pickup:GetSprite()
        if spr then
            if anim.phase == "before" then
                local add = (anim.maxAdd or 0.6) * t
                spr.Color = Color(1.0, 1.0, 1.0, 1.0, add, add, add)
            elseif anim.phase == "after" then
                local add = (anim.maxAdd or 0.6) * (1.0 - t)
                spr.Color = Color(1.0, 1.0, 1.0, 1.0, add, add, add)
            end
        end
        if anim.frames <= 0 then
            if spr then
                spr.Color = Color(1, 1, 1, 1, 0, 0, 0)
            end
            if anim.soundId then
                SFXManager():Stop(anim.soundId)
            end
            ConchBlessing.voiddagger._upgradeAnim = nil
        end
    end
end

-- Debug: print once on pickup
ConchBlessing.voiddagger.onPlayerUpdate = function(_, player)
    if not player then return end
    if not VOID_DAGGER_ID or VOID_DAGGER_ID == -1 then return end
    local has = player:HasCollectible(VOID_DAGGER_ID)
    local pdata = player:GetData()
    pdata._conch_void_dagger_had = pdata._conch_void_dagger_had or false
    if has and not pdata._conch_void_dagger_had then
        pdata._conch_void_dagger_had = true
        if ConchBlessing and ConchBlessing.printDebug then
            local S = getShotsPerSecond(player)
            local D = player.MaxFireDelay or 0
            local R = getDisplayRange(player)
            local radius = computeRingRadiusFromRange(player)
            local pBase = computeProcChanceFromS(S)
            local p, factor, L = applyLuckBonus(pBase, player.Luck)
            ConchBlessing.printDebug(string.format(
                "VoidDagger PICKUP: pBase=%.2f%% pFinal=%.2f%% (x%.1f @Luck=%.1f) S=%.2f D=%.2f R=%.2f radius=%.2f",
                pBase * 100.0, p * 100.0, factor, L, S, D, R, radius
            ))
        end
    end
end

