local require = ConchBlessingRequire or require -- reloadable loader, see main.lua
-- 인 (Tiger), 산군: the mountain lord.
--
-- In the folktale the soul of someone a tiger has eaten becomes a 창귀, a ghost
-- that serves the tiger and lures the next victim to it. Here every enemy the
-- holder kills has a 1/3 chance for each copy they hold (three copies make it
-- certain) to rise as a 창귀 that flies at an enemy and explodes for three times
-- the holder's damage; every enemy it hits is feared for three seconds. A kill
-- by a 창귀 counts as the holder's kill too, so a 창귀 may raise the next one
-- (user decision 2026-10-31).
--
-- The 창귀 is the vanilla Purgatory soul (effect 1000.189.1), spawned with the
-- holder as its spawner, so the engine raises it, picks its enemy and flies it.
-- When it reaches the enemy it bursts into Ghost Bombs' explosion (1000.144.1).
-- That explosion ticks twice the player's damage up to four times on everything
-- around it, with no damage source at all (measured in game 2026-10-31 with
-- `conch_test tiger ghost_native`), so its own damage could neither be 3x nor
-- name its owner. Each of its ticks is cancelled, and the first time it reaches
-- an enemy that enemy takes one hit of 3x the holder's damage with the explosion
-- as the source, which leads back to the holder for kill credit and other
-- items' hit effects. The engine still decides what the explosion reaches.
--
-- A kill is the holder's when the enemy died from damage (MC_POST_ENTITY_KILL
-- reports HP at or below 0; a direct Kill() keeps its HP, measured the same day)
-- and the last hit it took belongs to that player through DamageProvenance.
-- The hit is read in MC_ENTITY_TAKE_DMG at LATE priority, after other mods
-- have changed or cancelled it; the enemy dies on the next update, when the
-- engine applies its damage. Everything here is base API, so the item needs
-- no REPENTOGON. Nothing is saved: 창귀 last only as long as their room.
local DamageProvenance = require("scripts.lib.damage_provenance")
local EnemyUtils = require("scripts.lib.enemy_utils")

local M = {}
ConchBlessing.tiger = M

local TIGER_ID = Isaac.GetItemIdByName("Tiger")
local PROC_KEY = "tiger_changgwi"
local HIT_KEY = "__ConchBlessingTigerHit"
local GHOST_SUBTYPE = 1 -- Purgatory: 0 is the rift, 1 the soul
local BLAST_SUBTYPE = 1 -- Enemy Ghost: 1 is its explosion

local callbackPriority = rawget(_G, "CallbackPriority")
local EARLY = type(callbackPriority) == "table" and tonumber(callbackPriority.EARLY) or -100
local LATE = type(callbackPriority) == "table" and tonumber(callbackPriority.LATE) or 100

M.data = {
    -- 인 is third of the twelve, so its numbers are threes.
    chancePerCopy = 1 / 3,   -- a kill raises a 창귀 this often for each copy held
    damageMultiplier = 3,    -- of the holder's damage, once to each enemy the explosion reaches
    fearFrames = 90,         -- three seconds of fear for each enemy it hits
    nativeMultiplier = 2,    -- the vanilla explosion ticks this much of the spawner's damage
    blastMatch = 80,         -- an explosion this close to a 창귀 that just burst is that 창귀's
    blastReach = 160,        -- a sourceless tick this close to our explosion is one of its ticks
}

local souls = {}   -- [GetPtrHash(soul)] = { ref, owner, provenance, x, y, burst }
local blasts = {}  -- [GetPtrHash(blast)] = { ref, owner, provenance, damage, hit = {}, queue = {} }
-- Runtime evidence for conch_test tiger; never saved.
local evidence
local function resetEvidence()
    evidence = { kills = 0, rolls = 0, spawned = 0, claimed = 0, cancelled = 0, hits = 0, feared = 0, lastRoll = nil }
end
resetEvidence()

local function isActingPlayer(player)
    if not player then return false end
    if type(player.IsDead) == "function" and player:IsDead() then return false end
    if type(player.IsCoopGhost) == "function" and player:IsCoopGhost() then return false end
    return true
end

-- ------------------------------------------------------------------ pure rules
-- The chance a kill raises a 창귀 for a player holding `copies`: 1/3 each, at most 1.
local function chanceFor(copies)
    return math.min(1, math.max(0, math.floor(tonumber(copies) or 0)) * M.data.chancePerCopy)
end

local function spawns(roll, chance)
    return roll < chance
end

-- One hit per enemy: the explosion's damage for a holder whose damage is `damage`.
local function blastDamage(damage)
    return M.data.damageMultiplier * (tonumber(damage) or 0)
end

local function near(a, b) return math.abs(a - b) <= 1e-3 * math.max(1, math.abs(b)) end

-- ------------------------------------------------------------------ ownership
function M.copies(player)
    if TIGER_ID <= 0 or not player then return 0 end
    return player:GetCollectibleNum(TIGER_ID)
end

local function anyHolder()
    if TIGER_ID <= 0 then return false end
    for index = 0, Game():GetNumPlayers() - 1 do
        local player = Isaac.GetPlayer(index)
        if player and player:GetCollectibleNum(TIGER_ID) > 0 then return true end
    end
    return false
end

local function ownerOf(record)
    local entity = record and record.owner and record.owner.Ref
    local player = entity and entity:ToPlayer()
    if player and player:Exists() then return player end
    return nil
end

-- The live explosion a sourceless tick on `entity` belongs to, if any.
local function blastFor(entity, amount, flags, source)
    if not next(blasts) or flags ~= 0 or (source and source.Entity) then return nil end
    if entity.Type == EntityType.ENTITY_PLAYER then return nil end
    for _, blast in pairs(blasts) do
        local effect = blast.ref.Ref
        if effect and effect:Exists() then
            local owner = ownerOf(blast)
            local damage = owner and owner.Damage or blast.damage
            local fits = near(amount, effect.CollisionDamage) or near(amount, M.data.nativeMultiplier * damage)
            if fits and entity.Position:Distance(effect.Position) <= M.data.blastReach + entity.Size then
                return blast
            end
        end
    end
    return nil
end

-- ------------------------------------------------------------------ kills
-- LATE: the hit as it will land. Each enemy remembers who hit it last; an
-- explosion tick cancelled at EARLY is not a hit.
function M.onTakeDamageLate(_, entity, amount, flags, source)
    amount = tonumber(amount) or 0
    if amount <= 0 or not anyHolder() then return nil end
    local npc = entity and entity:ToNPC()
    if not npc or blastFor(npc, amount, flags, source) then return nil end
    local attack = source and source.Entity
    local player = attack and DamageProvenance.getPlayerOwner(attack)
    npc:GetData()[HIT_KEY] = player and {
        owner = EntityPtr(player),
        provenance = DamageProvenance.getSnapshot(attack),
    } or false
    return nil
end

local function raise(player, npc, record)
    local rng = player:GetCollectibleRNG(TIGER_ID)
    local chance = chanceFor(M.copies(player))
    local roll = rng:RandomFloat()
    evidence.rolls = evidence.rolls + 1
    evidence.lastRoll = { roll = roll, chance = chance }
    if not spawns(roll, chance) then return nil end
    local seed = rng:Next()
    if seed == 0 then seed = 1 end
    local soul = Game():Spawn(EntityType.ENTITY_EFFECT, EffectVariant.PURGATORY, npc.Position, Vector.Zero,
        player, GHOST_SUBTYPE, seed)
    soul = soul and soul:ToEffect()
    if not soul then return nil end
    DamageProvenance.markTriggeredAttack(soul, PROC_KEY, record.provenance, PROC_KEY)
    souls[GetPtrHash(soul)] = { ref = EntityPtr(soul), owner = EntityPtr(player),
        provenance = DamageProvenance.getSnapshot(soul), x = soul.Position.X, y = soul.Position.Y }
    evidence.spawned = evidence.spawned + 1
    return soul
end

function M.onEntityKill(_, entity)
    local npc = entity and entity:ToNPC()
    if not npc then return end
    local data = npc:GetData()
    local record = data[HIT_KEY]
    if record == nil then return end
    data[HIT_KEY] = nil -- one roll per death
    -- A direct Kill() leaves the enemy's HP above 0; only a death by damage counts.
    if not record or npc.HitPoints > 0 or not EnemyUtils.isMonsterKind(npc) then return end
    local player = ownerOf(record)
    if not isActingPlayer(player) or M.copies(player) <= 0 then return end
    evidence.kills = evidence.kills + 1
    raise(player, npc, record)
end

-- ------------------------------------------------------------------ explosion
-- A 창귀 bursting: remember where, so the explosion that follows can be claimed.
function M.onEntityRemove(_, entity)
    if entity.Type ~= EntityType.ENTITY_EFFECT or entity.Variant ~= EffectVariant.PURGATORY then return end
    local soul = souls[GetPtrHash(entity)]
    if soul and not soul.burst then
        soul.burst, soul.x, soul.y = true, entity.Position.X, entity.Position.Y
    end
end

local function claimSoul(blast)
    local spawner = blast.SpawnerEntity and blast.SpawnerEntity:ToPlayer()
    if not spawner then return nil end
    local best, bestHash, bestDistance
    for hash, soul in pairs(souls) do
        local owner = ownerOf(soul)
        if owner and GetPtrHash(owner) == GetPtrHash(spawner) then
            local ref = soul.ref.Ref
            if not soul.burst and ref and ref:Exists() then soul.x, soul.y = ref.Position.X, ref.Position.Y end
            local distance = blast.Position:Distance(Vector(soul.x, soul.y))
            if distance <= M.data.blastMatch and (not bestDistance or distance < bestDistance) then
                best, bestHash, bestDistance = soul, hash, distance
            end
        end
    end
    if bestHash then souls[bestHash] = nil end
    return best
end

function M.onEffectInit(_, effect)
    if effect.Variant ~= EffectVariant.ENEMY_GHOST or effect.SubType ~= BLAST_SUBTYPE or not next(souls) then return end
    local soul = claimSoul(effect)
    if not soul then return end
    DamageProvenance.markTriggeredAttack(effect, PROC_KEY, soul.provenance, PROC_KEY)
    local owner = ownerOf(soul)
    blasts[GetPtrHash(effect)] = { ref = EntityPtr(effect), owner = soul.owner,
        provenance = DamageProvenance.getSnapshot(effect), damage = owner and owner.Damage or 0, hit = {}, queue = {} }
    evidence.claimed = evidence.claimed + 1
end

-- EARLY: cancel the vanilla explosion's own ticks before anything counts them,
-- and queue our single hit for the first one on each enemy.
function M.onTakeDamageEarly(_, entity, amount, flags, source)
    local blast = blastFor(entity, tonumber(amount) or 0, flags, source)
    if not blast then return nil end
    evidence.cancelled = evidence.cancelled + 1
    local key = GetPtrHash(entity)
    if not blast.hit[key] then
        blast.hit[key] = true
        blast.queue[#blast.queue + 1] = EntityPtr(entity)
    end
    return false
end

local function strike(blast)
    local effect = blast.ref.Ref
    local owner = ownerOf(blast)
    local damage = blastDamage(owner and owner.Damage or blast.damage)
    for _, ref in ipairs(blast.queue) do
        local target = ref.Ref
        if target and target:Exists() and not target:IsDead() and (effect and effect:Exists() or owner) then
            if effect and effect:Exists() then
                target:TakeDamage(damage, 0, EntityRef(effect), 0)
            else
                -- The explosion ended this update: the holder is the source, with its lineage.
                DamageProvenance.withTriggeredSource(owner, PROC_KEY, blast.provenance, PROC_KEY, function()
                    target:TakeDamage(damage, 0, EntityRef(owner), 0)
                end)
            end
            evidence.hits = evidence.hits + 1
            local npc = target:ToNPC()
            if EnemyUtils.isMonsterKind(npc) then
                npc:AddFear(EntityRef(owner or effect), M.data.fearFrames)
                evidence.feared = evidence.feared + 1
            end
        end
    end
    blast.queue = {}
end

-- After every entity has updated: land the queued hits, and forget 창귀 that
-- burst without an explosion and explosions that are over.
function M.onUpdate()
    for hash, blast in pairs(blasts) do
        if #blast.queue > 0 then strike(blast) end
        local effect = blast.ref.Ref
        if not (effect and effect:Exists()) then blasts[hash] = nil end
    end
    for hash, soul in pairs(souls) do
        local ref = soul.ref.Ref
        if soul.burst or not (ref and ref:Exists()) then
            souls[hash] = nil
        else
            soul.x, soul.y = ref.Position.X, ref.Position.Y
        end
    end
end

-- A new room, game start, exit and unload drop every 창귀 and explosion record.
function M.reset()
    souls, blasts = {}, {}
end

M._test = {
    chanceFor = chanceFor,
    spawns = spawns,
    blastDamage = blastDamage,
    souls = function() return souls end,
    blasts = function() return blasts end,
    evidence = function() return evidence end,
    resetEvidence = resetEvidence,
    procKey = PROC_KEY,
    hitKey = HIT_KEY,
}

-- Priorities and filters the ItemData registrar cannot express.
if type(ConchBlessing.AddPriorityCallback) == "function" then
    ConchBlessing:AddPriorityCallback(ModCallbacks.MC_ENTITY_TAKE_DMG, EARLY, M.onTakeDamageEarly)
    ConchBlessing:AddPriorityCallback(ModCallbacks.MC_ENTITY_TAKE_DMG, LATE, M.onTakeDamageLate)
else
    ConchBlessing:AddCallback(ModCallbacks.MC_ENTITY_TAKE_DMG, M.onTakeDamageEarly)
    ConchBlessing:AddCallback(ModCallbacks.MC_ENTITY_TAKE_DMG, M.onTakeDamageLate)
end
ConchBlessing:AddCallback(ModCallbacks.MC_POST_EFFECT_INIT, M.onEffectInit, EffectVariant.ENEMY_GHOST)
ConchBlessing:AddCallback(ModCallbacks.MC_POST_ENTITY_REMOVE, M.onEntityRemove, EntityType.ENTITY_EFFECT)

return M
