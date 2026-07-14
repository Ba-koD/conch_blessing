local DamageProvenance = {}

local DATA_KEY = "__ConchBlessingDamageProvenance"
local ATTACK_STATE_KEY = "__ConchBlessingDamageAttackState"
-- Entity ownership commonly crosses player -> familiar/effect -> weapon -> child.
-- Keep the walk bounded for malformed/cyclic relationships while allowing real
-- attack chains to retain their provenance.
local MAX_LINEAGE_DEPTH = 12
local callbacksRegistered = false

local function copyValue(value, seen)
    if type(value) ~= "table" then
        return value
    end

    seen = seen or {}
    if seen[value] then
        return seen[value]
    end

    local copy = {}
    seen[value] = copy
    for key, childValue in pairs(value) do
        copy[copyValue(key, seen)] = copyValue(childValue, seen)
    end
    return copy
end

local function copyRecord(record)
    return copyValue(record or {})
end

local function hasEntries(value)
    return type(value) == "table" and next(value) ~= nil
end

local function recordBlocksAllHitProcs(record)
    if type(record) ~= "table" then
        return false
    end
    if record.blocksAllHitProcs == true then
        return true
    end

    -- Compatibility for records produced before proc-specific chains existed.
    return record.triggersHitProcs == false and not hasEntries(record.procChain)
end

local function mergeRecord(target, record)
    if type(record) ~= "table" then
        return target
    end
    target = target or {}

    for key, value in pairs(record) do
        if key ~= "procChain"
            and key ~= "triggersHitProcs"
            and key ~= "blocksAllHitProcs"
            and key ~= "scopedAttackState"
            and target[key] == nil
        then
            target[key] = copyValue(value)
        end
    end

    if hasEntries(record.procChain) then
        target.procChain = target.procChain or {}
        for procKey, triggered in pairs(record.procChain) do
            if triggered then
                target.procChain[procKey] = true
            end
        end
    end

    if recordBlocksAllHitProcs(record) then
        target.blocksAllHitProcs = true
        target.triggersHitProcs = false
    end

    return target
end

local function mergeSnapshots(...)
    local merged = nil
    for index = 1, select("#", ...) do
        merged = mergeRecord(merged, select(index, ...))
    end
    if not merged then
        merged = {}
    end
    merged.procChain = merged.procChain or {}
    return merged
end

function DamageProvenance.mark(entity, record)
    if not entity or type(entity.GetData) ~= "function" then
        return entity
    end

    entity:GetData()[DATA_KEY] = copyRecord(record)
    return entity
end

--- Legacy global opt-out. New hit procs should use markTriggeredAttack so only
--- their own causal lineage is excluded.
function DamageProvenance.markSecondaryAttack(entity, origin)
    return DamageProvenance.mark(entity, {
        origin = origin,
        secondary = true,
        triggersHitProcs = false,
    })
end

--- Mark an attack created by a damage proc while preserving every proc already
--- present in its ancestry. A consumer rejects only when its own proc key is in
--- this chain, so an unmarked attack of the same entity/weapon type still works.
function DamageProvenance.markTriggeredAttack(entity, procKey, inheritedSnapshot, originLabel)
    local record = mergeSnapshots(DamageProvenance.resolve(entity), inheritedSnapshot)
    if procKey ~= nil then
        record.procChain[procKey] = true
    end
    record.origin = originLabel or procKey or record.origin
    record.secondary = true
    return DamageProvenance.mark(entity, record)
end

--- Legacy scoped global opt-out. Prefer withTriggeredSource for proc chains.
function DamageProvenance.withSecondarySource(entity, origin, callback)
    if type(callback) ~= "function" then
        return
    end
    if not entity or type(entity.GetData) ~= "function" then
        return callback()
    end

    local data = entity:GetData()
    local previous = data[DATA_KEY]
    data[DATA_KEY] = {
        origin = origin,
        secondary = true,
        triggersHitProcs = false,
    }

    local results = table.pack(pcall(callback))
    data[DATA_KEY] = previous
    if not results[1] then
        error(results[2], 0)
    end

    return table.unpack(results, 2, results.n)
end

--- Temporarily mark a collapsed damage source (usually a player passed to a
--- direct damage API) with an inherited proc chain for the duration of callback.
function DamageProvenance.withTriggeredSource(entity, procKey, inheritedSnapshot, originLabel, callback)
    if type(callback) ~= "function" then
        return
    end
    if not entity or type(entity.GetData) ~= "function" then
        return callback()
    end

    local data = entity:GetData()
    local previous = data[DATA_KEY]
    local record = mergeSnapshots(previous, inheritedSnapshot)
    if procKey ~= nil then
        record.procChain[procKey] = true
    end
    record.origin = originLabel or procKey or record.origin
    record.secondary = true
    -- Direct-damage APIs can collapse the source to the player. Give only this
    -- synchronous call its own attack state; mergeSnapshots intentionally does
    -- not propagate this ephemeral state into causal descendants.
    record.scopedAttackState = { claims = {} }
    data[DATA_KEY] = copyRecord(record)

    local results = table.pack(pcall(callback))
    data[DATA_KEY] = previous
    if not results[1] then
        error(results[2], 0)
    end

    return table.unpack(results, 2, results.n)
end

function DamageProvenance.get(entity)
    if not entity or type(entity.GetData) ~= "function" then
        return nil
    end

    local record = entity:GetData()[DATA_KEY]
    return type(record) == "table" and record or nil
end

local function resolveRecord(entity, depth, visited, result)
    if not entity or depth > MAX_LINEAGE_DEPTH or visited[entity] then
        return result
    end
    visited[entity] = true

    result = mergeRecord(result, DamageProvenance.get(entity))
    result = resolveRecord(entity.Parent, depth + 1, visited, result)
    return resolveRecord(entity.SpawnerEntity, depth + 1, visited, result)
end

function DamageProvenance.resolve(entity)
    return resolveRecord(entity, 0, {}, nil)
end

--- Return an isolated plain-table snapshot suitable for deferred runtime work.
--- Callers can safely store/reuse it because nested proc-chain state is copied.
function DamageProvenance.getSnapshot(entity)
    return mergeSnapshots(DamageProvenance.resolve(entity))
end

function DamageProvenance.inherit(entity, sourceEntity)
    local sourceRecord = DamageProvenance.resolve(sourceEntity)
    if not sourceRecord then
        return false
    end

    local record = mergeSnapshots(DamageProvenance.resolve(entity), sourceRecord)
    DamageProvenance.mark(entity, record)
    return true
end

function DamageProvenance.getSourceEntity(source, extraSource)
    local extraEntity = extraSource and extraSource.Entity or nil
    if extraEntity then
        return extraEntity
    end

    return source and source.Entity or nil
end

local function isSnapshotHitProcEligible(snapshot, procKey)
    if recordBlocksAllHitProcs(snapshot) then
        return false
    end

    local procChain = snapshot and snapshot.procChain or nil
    if procKey ~= nil then
        return not (procChain and procChain[procKey] == true)
    end

    -- Calls without a proc key retain the old conservative behavior.
    return not hasEntries(procChain)
end

function DamageProvenance.isHitProcEligible(entity, procKey)
    return isSnapshotHitProcEligible(DamageProvenance.resolve(entity), procKey)
end

local function toPlayer(entity)
    if not entity or type(entity.ToPlayer) ~= "function" then
        return nil
    end

    local ok, player = pcall(entity.ToPlayer, entity)
    return ok and player or nil
end

local function toFamiliar(entity)
    if not entity or type(entity.ToFamiliar) ~= "function" then
        return nil
    end

    local ok, familiar = pcall(entity.ToFamiliar, entity)
    return ok and familiar or nil
end

local function getCanonicalAttackEntity(entity)
    if not entity then
        return nil
    end

    -- Melee swing hitboxes can be separate EntityKnife instances while still
    -- belonging to one main knife attack. REPENTOGON exposes that exact link.
    if type(entity.ToKnife) == "function" then
        local okKnife, knife = pcall(entity.ToKnife, entity)
        if okKnife and knife and type(knife.GetHitboxParentKnife) == "function" then
            local okParent, parentKnife = pcall(knife.GetHitboxParentKnife, knife)
            if okParent and parentKnife then
                return parentKnife
            end
        end
    end

    return entity
end

local function claimProc(state, procKey)
    if type(state) ~= "table" then
        return false
    end

    state.claims = type(state.claims) == "table" and state.claims or {}
    if state.claims[procKey] == true then
        return false
    end

    state.claims[procKey] = true
    return true
end

--- Start a new semantic attack on an entity that the engine reuses across
--- weapon triggers (for example a weapon's main knife/laser entity).
function DamageProvenance.beginAttackInstance(entity, ownerPlayer)
    local attackEntity = getCanonicalAttackEntity(entity)
    if not attackEntity or type(attackEntity.GetData) ~= "function" then
        return nil
    end

    local state = {
        claims = {},
        ownerPlayer = toPlayer(ownerPlayer),
    }
    attackEntity:GetData()[ATTACK_STATE_KEY] = state
    return attackEntity
end

--- Atomically consume one proc opportunity for an exact attack instance.
--- This state is deliberately separate from procChain: causal provenance is
--- inherited by descendants, while a newly-created attack gets fresh claims.
function DamageProvenance.tryClaimAttackProc(entity, procKey)
    if procKey == nil then
        return false
    end

    local attackEntity = getCanonicalAttackEntity(entity)
    if not attackEntity or type(attackEntity.GetData) ~= "function" then
        return false
    end

    -- A producer may temporarily mark a collapsed source with an exact scoped
    -- attack identity. Use it before considering entity-lifetime state.
    local provenance = DamageProvenance.get(attackEntity)
    local scopedState = provenance and provenance.scopedAttackState or nil
    if type(scopedState) == "table" then
        return claimProc(scopedState, procKey)
    end

    local data = attackEntity:GetData()
    local state = data[ATTACK_STATE_KEY]

    -- A bare player or familiar body is an owner/long-lived contact hitbox, not
    -- a discrete attack. Only an exact producer-opened state may make the body
    -- itself claimable; otherwise storing a claim would suppress future attacks.
    if (toPlayer(attackEntity) or toFamiliar(attackEntity)) and type(state) ~= "table" then
        return false
    end

    if type(state) ~= "table" then
        state = { claims = {} }
        data[ATTACK_STATE_KEY] = state
    end

    return claimProc(state, procKey)
end

local function isSamePlayer(first, second)
    if first == second then
        return true
    end
    if not (first and second) then
        return false
    end

    return first.InitSeed ~= nil
        and first.InitSeed == second.InitSeed
        and first.Index ~= nil
        and first.Index == second.Index
end

--- REPENTOGON reports one semantic weapon trigger and exposes the active main
--- entity. Only reusable melee EntityKnife attacks need their entity-lifetime
--- claim reopened here. Fresh tears, bombs, effects, and lasers already have a
--- fresh GetData table; resetting a live laser could incorrectly reopen an old
--- Tech X ring or continuous beam. Never infer resets from frames or cooldowns.
function DamageProvenance.onWeaponFired(_, _fireDirection, _fireAmount, owner, weapon)
    if not weapon or type(weapon.GetMainEntity) ~= "function" then
        return
    end

    local ok, mainEntity = pcall(weapon.GetMainEntity, weapon)
    if not (ok and mainEntity and type(mainEntity.ToKnife) == "function") then
        return
    end

    local okKnife, knife = pcall(mainEntity.ToKnife, mainEntity)
    if not (okKnife and knife) then
        return
    end

    local ownerPlayer = DamageProvenance.getPlayerOwner(owner)
    local attackPlayer = DamageProvenance.getPlayerOwner(mainEntity)
    if ownerPlayer and isSamePlayer(ownerPlayer, attackPlayer) then
        DamageProvenance.beginAttackInstance(mainEntity, ownerPlayer)
    end
end

local function resolvePlayerOwner(entity, depth, visited)
    if not entity or depth > MAX_LINEAGE_DEPTH or visited[entity] then
        return nil
    end
    visited[entity] = true

    local player = toPlayer(entity)
    if player then
        return player
    end

    -- Familiar attacks normally point at the familiar as their immediate
    -- spawner. EntityFamiliar.Player is the semantic owner even when an
    -- intermediate attack entity no longer points directly at the player.
    local familiar = toFamiliar(entity)
    if familiar then
        player = toPlayer(familiar.Player)
        if player then
            return player
        end
    end

    return resolvePlayerOwner(entity.SpawnerEntity, depth + 1, visited)
        or resolvePlayerOwner(entity.Parent, depth + 1, visited)
end

--- Resolve a player through the actual attack's ownership lineage.
--- This intentionally classifies by ownership rather than weapon/entity type,
--- so tears, lasers, knives, bombs, effects, and familiar-fired attacks share one path.
function DamageProvenance.getPlayerOwner(entity)
    return resolvePlayerOwner(entity, 0, {})
end

local function getAttackStatePlayer(entity)
    local attackEntity = getCanonicalAttackEntity(entity)
    if not attackEntity or type(attackEntity.GetData) ~= "function" then
        return nil
    end

    local state = attackEntity:GetData()[ATTACK_STATE_KEY]
    return type(state) == "table" and toPlayer(state.ownerPlayer) or nil
end

--- Resolve an applied-damage callback to a proc-eligible player-owned attack.
--- REPENTOGON exposes the real hitbox in ExtraSource for attacks such as lasers
--- and knives, while Source may retain the owning player/familiar. Check both
--- branches for blocked provenance before resolving ownership from either one.
--- Returns the canonical attack entity, its player owner, and a merged provenance
--- snapshot, or nil when ownership is unavailable or this proc key already ran.
function DamageProvenance.getEligiblePlayerAttack(source, extraSource, procKey)
    local attackEntity = DamageProvenance.getSourceEntity(source, extraSource)
    if not attackEntity then
        return nil
    end

    local sourceEntity = source and source.Entity or nil
    local canonicalAttackEntity = getCanonicalAttackEntity(attackEntity)
    local snapshot = mergeSnapshots(
        DamageProvenance.resolve(attackEntity),
        canonicalAttackEntity ~= attackEntity and DamageProvenance.resolve(canonicalAttackEntity) or nil,
        sourceEntity ~= attackEntity and DamageProvenance.resolve(sourceEntity) or nil
    )
    if not isSnapshotHitProcEligible(snapshot, procKey) then
        return nil
    end

    local player = getAttackStatePlayer(canonicalAttackEntity)
        or getAttackStatePlayer(attackEntity)
        or DamageProvenance.getPlayerOwner(canonicalAttackEntity)
        or DamageProvenance.getPlayerOwner(attackEntity)
        or DamageProvenance.getPlayerOwner(sourceEntity)
    if not player then
        return nil
    end

    return canonicalAttackEntity, player, snapshot
end

--- Legacy tear-only classifier retained for base collision call sites.
function DamageProvenance.getEligibleDirectTear(source, extraSource)
    local sourceEntity = DamageProvenance.getSourceEntity(source, extraSource)
    if not sourceEntity or type(sourceEntity.ToTear) ~= "function" then
        return nil
    end

    local tear = sourceEntity:ToTear()
    if not tear then
        return nil
    end

    if not DamageProvenance.isHitProcEligible(tear) then
        return nil
    end

    return tear
end

function DamageProvenance.hasAppliedDamageCallback()
    local repentogon = rawget(_G, "REPENTOGON")
    return type(repentogon) == "table"
        and repentogon.Real == true
        and type(ModCallbacks.MC_POST_ENTITY_TAKE_DMG) == "number"
end

function DamageProvenance.getDirectPlayerOwner(entity)
    if not entity then
        return nil
    end

    local spawner = entity.SpawnerEntity
    if spawner and type(spawner.ToPlayer) == "function" then
        local player = spawner:ToPlayer()
        if player then
            return player
        end
    end

    local parent = entity.Parent
    if parent and type(parent.ToPlayer) == "function" then
        return parent:ToPlayer()
    end

    return nil
end

local function inheritFromParentOrSpawner(entity)
    if not entity then
        return false
    end

    local record = DamageProvenance.resolve(entity)
    if not record then
        return false
    end

    DamageProvenance.mark(entity, record)
    return true
end

function DamageProvenance.onTearInit(_, tear)
    inheritFromParentOrSpawner(tear)
end

function DamageProvenance.onBombInit(_, bomb)
    inheritFromParentOrSpawner(bomb)
end

function DamageProvenance.onLaserInit(_, laser)
    inheritFromParentOrSpawner(laser)
end

function DamageProvenance.onKnifeInit(_, knife)
    inheritFromParentOrSpawner(knife)
end

function DamageProvenance.onEffectInit(_, effect)
    inheritFromParentOrSpawner(effect)
end

function DamageProvenance.onProjectileInit(_, projectile)
    inheritFromParentOrSpawner(projectile)
end

function DamageProvenance.onFamiliarInit(_, familiar)
    inheritFromParentOrSpawner(familiar)
end

function DamageProvenance.onSplitTear(_, tear, sourceEntity, _splitType)
    if tear and sourceEntity then
        DamageProvenance.inherit(tear, sourceEntity)
    end
end

function DamageProvenance.registerCallbacks(mod)
    if callbacksRegistered or not mod or type(mod.AddCallback) ~= "function" then
        return callbacksRegistered
    end

    mod:AddCallback(ModCallbacks.MC_POST_TEAR_INIT, DamageProvenance.onTearInit)
    mod:AddCallback(ModCallbacks.MC_POST_BOMB_INIT, DamageProvenance.onBombInit)
    mod:AddCallback(ModCallbacks.MC_POST_LASER_INIT, DamageProvenance.onLaserInit)

    -- These callbacks exist in current base builds, but remain capability
    -- checked because this repository has not pinned a minimum executable.
    local optionalInitCallbacks = {
        { ModCallbacks.MC_POST_KNIFE_INIT, DamageProvenance.onKnifeInit },
        { ModCallbacks.MC_POST_EFFECT_INIT, DamageProvenance.onEffectInit },
        { ModCallbacks.MC_POST_PROJECTILE_INIT, DamageProvenance.onProjectileInit },
        { ModCallbacks.MC_FAMILIAR_INIT, DamageProvenance.onFamiliarInit },
    }
    for _, registration in ipairs(optionalInitCallbacks) do
        if type(registration[1]) == "number" then
            mod:AddCallback(registration[1], registration[2])
        end
    end

    local repentogon = rawget(_G, "REPENTOGON")
    local splitCallback = ModCallbacks.MC_POST_FIRE_SPLIT_TEAR
    if type(repentogon) == "table"
        and repentogon.Real == true
        and type(splitCallback) == "number"
    then
        mod:AddCallback(splitCallback, DamageProvenance.onSplitTear)
    end

    local weaponFiredCallback = ModCallbacks.MC_POST_TRIGGER_WEAPON_FIRED
    if type(repentogon) == "table"
        and repentogon.Real == true
        and type(weaponFiredCallback) == "number"
    then
        mod:AddCallback(weaponFiredCallback, DamageProvenance.onWeaponFired)
    end

    callbacksRegistered = true
    return true
end

return DamageProvenance
