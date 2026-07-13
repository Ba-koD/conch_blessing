local DamageProvenance = {}

local DATA_KEY = "__ConchBlessingDamageProvenance"
local MAX_LINEAGE_DEPTH = 4
local callbacksRegistered = false

local function copyRecord(record)
    local copy = {}
    for key, value in pairs(record or {}) do
        copy[key] = value
    end
    return copy
end

function DamageProvenance.mark(entity, record)
    if not entity or type(entity.GetData) ~= "function" then
        return entity
    end

    entity:GetData()[DATA_KEY] = copyRecord(record)
    return entity
end

function DamageProvenance.markSecondaryAttack(entity, origin)
    return DamageProvenance.mark(entity, {
        origin = origin,
        secondary = true,
        triggersHitProcs = false,
    })
end

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

function DamageProvenance.get(entity)
    if not entity or type(entity.GetData) ~= "function" then
        return nil
    end

    local record = entity:GetData()[DATA_KEY]
    return type(record) == "table" and record or nil
end

local function resolveRecord(entity, depth, visited)
    if not entity or depth > MAX_LINEAGE_DEPTH or visited[entity] then
        return nil
    end
    visited[entity] = true

    local record = DamageProvenance.get(entity)
    if record and record.triggersHitProcs == false then
        return record
    end

    local parentRecord = resolveRecord(entity.Parent, depth + 1, visited)
    if parentRecord and parentRecord.triggersHitProcs == false then
        return parentRecord
    end

    local spawnerRecord = resolveRecord(entity.SpawnerEntity, depth + 1, visited)
    if spawnerRecord and spawnerRecord.triggersHitProcs == false then
        return spawnerRecord
    end

    return record or parentRecord or spawnerRecord
end

function DamageProvenance.resolve(entity)
    return resolveRecord(entity, 0, {})
end

function DamageProvenance.inherit(entity, sourceEntity)
    local record = DamageProvenance.resolve(sourceEntity)
    if not record then
        return false
    end

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

function DamageProvenance.isHitProcEligible(entity)
    local record = DamageProvenance.resolve(entity)
    return not record or record.triggersHitProcs ~= false
end

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

    return DamageProvenance.inherit(entity, entity.Parent)
        or DamageProvenance.inherit(entity, entity.SpawnerEntity)
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

    local repentogon = rawget(_G, "REPENTOGON")
    local splitCallback = ModCallbacks.MC_POST_FIRE_SPLIT_TEAR
    if type(repentogon) == "table"
        and repentogon.Real == true
        and type(splitCallback) == "number"
    then
        mod:AddCallback(splitCallback, DamageProvenance.onSplitTear)
    end

    callbacksRegistered = true
    return true
end

return DamageProvenance
