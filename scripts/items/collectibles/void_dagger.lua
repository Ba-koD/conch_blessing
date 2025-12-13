ConchBlessing.voiddagger = {}

-- config
ConchBlessing.voiddagger.data = {
    targetLockoutF = 20, -- per-target lockout frames
    Radius = 15,         -- ring radius
}

local VOID_DAGGER_ID = Isaac.GetItemIdByName("Void Dagger")

-- runtime guard map to avoid multi-trigger spam on the same enemy within a short window
ConchBlessing.voiddagger._lastProcFrameByNpc = {}
ConchBlessing.voiddagger._lastGlobalSpawnFrame = -999
ConchBlessing.voiddagger._upgradeAnim = nil

-- shots per second (SPS): S ≈ 30 / (MaxFireDelay + 1)
local function getShotsPerSecond(player)
    local maxDelay = player.MaxFireDelay or 0
    return math.max(1.0, 30.0 / (maxDelay + 1.0))
end

-- display range: R = TearRange / 40
local function getDisplayRange(player)
    local tr = player.TearRange
    return tr / 40.0
end

local function computeRingRadiusFromRange(player)
    return ConchBlessing.voiddagger.data.Radius
end

-- timeout frames by damage buckets: base 20, +5 per 10 damage (20, 25, 30, 35, 40 for dmg 0, 10, 20, 30, 40+)
local function computeTimeoutFromDamage(damage)
    local dmg = tonumber(damage) or 0
    if dmg < 0 then dmg = 0 end
    local bucket = math.floor(dmg / 10) -- 0~9→0, 10~19→1, 20~29→2, ...
    if bucket > 4 then bucket = 4 end -- max 5 stages (0~4)
    local timeout = 20 + (5 * bucket) -- 20 + 0, 5, 10, 15, 20 = 20, 25, 30, 35, 40
    return timeout
end

-- base proc chance: p = max(5%, (30 - SPS)%)
local function computeProcChanceFromS(shotsPerSecond)
    local s = tonumber(shotsPerSecond) or 0
    if s < 0 then s = 0 end
    -- (30 - s)% guaranteed 5%
    local p = (30.0 - s) / 100.0
    if p < 0.05 then p = 0.05 end
    if p > 1.0 then p = 1.0 end
    return p
end

-- luck bonus: pFinal = pBase × (1 + 0.1 × luck), capped at 100% (no luck limit, e.g. luck 190 → 20x multiplier)
local function applyLuckBonus(p, luck)
    local L = math.max(0.0, luck or 0.0) -- no upper limit on luck
    local factor = 1.0 + 0.1 * L
    local out = p * factor
    if out > 1.0 then out = 1.0 end -- cap at 100%
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

-- Spawn a Maw of Void ring at position with fixed lifetime and no black heart drops
local function spawnVoidRingAt(player, pos)
    -- Per request: use EntityPlayer:SpawnMawOfVoid
    -- First parameter is numeric (angle or mode). Use 0 and pin the laser at impact.
    local ring = player:SpawnMawOfVoid(0)
    if not ring then return end
    local laser = ring:ToLaser()
    if not laser then return end

    -- set timeout by player's damage
    local timeoutF = computeTimeoutFromDamage(player.Damage)
    if laser.SetTimeout then laser:SetTimeout(timeoutF) end
    laser.Timeout = timeoutF

    -- prevent black heart drops
    if laser.SetBlackHpDropChance then
        laser:SetBlackHpDropChance(0)
    elseif laser.BlackHpDropChance ~= nil then
        laser.BlackHpDropChance = 0
    end

    -- detach and lock at hit position
    laser.DisableFollowParent = true
    laser.Position = pos
    laser.ParentOffset = pos - player.Position
    laser.Velocity = Vector.Zero

    -- set radius
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

    -- compute proc chance
    local shotsPerSecond = getShotsPerSecond(player)          -- S ≈ 30/(MaxFireDelay+1)
    local pBase = computeProcChanceFromS(shotsPerSecond)      -- base chance
    local p, luckFactor, clampedLuck = applyLuckBonus(pBase, player.Luck) -- luck bonus
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
                "Void Dagger PROC: base=%.2f%% final=%.2f%% (luck x%.1f @Luck=%.1f) roll=%.3f S=%.2f D=%.2f R=%.2f radius=%.2f pos=(%.1f,%.1f) npcSeed=%s",
                pBase * 100.0, p * 100.0, luckFactor, clampedLuck, roll, shotsPerSecond, D, R, dbgRadius, hitPos.X, hitPos.Y, tostring(npc.InitSeed or npc.Index)
            ))
        end
    end

    return nil
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
            local p, luckFactor, clampedLuck = applyLuckBonus(pBase, player.Luck)
            ConchBlessing.printDebug(string.format(
                "Void Dagger: base=%.2f%% final=%.2f%% (luck x%.1f @Luck=%.1f) S=%.2f D=%.2f R=%.2f radius=%.2f",
                pBase * 100.0, p * 100.0, luckFactor, clampedLuck, S, D, R, radius
            ))
        end
    end
end


-- Optional cleanup each room to keep map light
ConchBlessing.voiddagger.onUpdate = function(_)
    ConchBlessing.template.onUpdate(ConchBlessing.voiddagger.data)
end

-- upgrade visuals
ConchBlessing.voiddagger.onBeforeChange = function(upgradePos, pickup, _)
    return ConchBlessing.template.neutral.onBeforeChange(upgradePos, pickup, ConchBlessing.voiddagger.data)
end

ConchBlessing.voiddagger.onAfterChange = function(upgradePos, pickup, _)
    ConchBlessing.template.neutral.onAfterChange(upgradePos, pickup, ConchBlessing.voiddagger.data)
end

-- EID dynamic description modifier to show current proc chance
if EID then
    EID:addDescriptionModifier("Void Dagger Proc Chance", function(descObj)
        -- Only modify Void Dagger description
        if descObj.ObjType == EntityType.ENTITY_PICKUP 
           and descObj.ObjVariant == PickupVariant.PICKUP_COLLECTIBLE 
           and descObj.ObjSubType == VOID_DAGGER_ID then
            
            local player = Isaac.GetPlayer(0)
            if not player then
                return descObj
            end
            
            -- Calculate current proc chance based on player stats
            local maxDelay = player.MaxFireDelay or 0
            local shotsPerSecond = math.max(1.0, 30.0 / (maxDelay + 1.0))
            
            -- Base chance: max(5%, (30 - SPS)%)
            local pBase = (30.0 - shotsPerSecond) / 100.0
            if pBase < 0.05 then pBase = 0.05 end
            if pBase > 1.0 then pBase = 1.0 end
            
            -- Apply luck bonus: pFinal = pBase × (1 + 0.1 × luck)
            local luck = math.max(0.0, player.Luck or 0.0)
            local luckFactor = 1.0 + 0.1 * luck
            local pFinal = pBase * luckFactor
            if pFinal > 1.0 then pFinal = 1.0 end
            
            -- Get current language for localization
            local ConchBlessing_Config = require("scripts.conch_blessing_config")
            local currentLang = ConchBlessing_Config.GetCurrentLanguage()
            
            -- Add proc chance info to description
            local procChanceText = ""
            if currentLang == "kr" then
                procChanceText = "#{{ColorYellow}}현재 발동 확률: " .. string.format("%.1f", pFinal * 100) .. "%{{CR}}"
                procChanceText = procChanceText .. " (기본: " .. string.format("%.1f", pBase * 100) .. "%, {{Luck}}x" .. string.format("%.1f", luckFactor) .. ")"
            else
                procChanceText = "#{{ColorYellow}}Current Proc Chance: " .. string.format("%.1f", pFinal * 100) .. "%{{CR}}"
                procChanceText = procChanceText .. " (Base: " .. string.format("%.1f", pBase * 100) .. "%, {{Luck}}x" .. string.format("%.1f", luckFactor) .. ")"
            end
            
            -- Append to existing description
            descObj.Description = descObj.Description .. procChanceText
            
            ConchBlessing.printDebug("[EID] Void Dagger: Added proc chance info - base=" .. string.format("%.1f", pBase * 100) .. "%, final=" .. string.format("%.1f", pFinal * 100) .. "%")
        end
        
        return descObj
    end)
    
    ConchBlessing.printDebug("[EID] Void Dagger: Description modifier registered")
end