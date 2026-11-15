local require = ConchBlessingRequire or require -- reloadable loader, see main.lua
-- 지뢰 (Landmine), the Magic Conch's neutral answer to Ipecac (user design
-- 2026-11-15). Ipecac turns every tear into a bomb; this keeps the tears as
-- they are and turns the ones that miss into traps. A tear the holder fired
-- that dies on the floor or against a wall or obstacle without having hit an
-- enemy leaves a mine where it fell. An enemy coming onto an armed mine sets
-- it off: every enemy within reach takes twice that tear's damage, and other
-- mines the blast reaches go off a moment later. Each player keeps at most ten
-- mines; laying another removes their oldest.
--
-- Mines never hurt a player (user decision 2026-11-15). The blast is dealt
-- here, to enemies only, never through the engine's explosion, which would
-- also hit players and break rocks; the vanilla bomb explosion is spawned only
-- as a picture.
--
-- REPENTOGON's MC_POST_TEAR_DEATH tells when a tear dies and its
-- MC_POST_TEAR_COLLISION that it really hit something, so the item needs
-- REPENTOGON. A tear is the holder's when the holder spawned it (familiars'
-- tears lay nothing). Mines are effects that last as long as their room;
-- nothing is saved.
local DamageProvenance = require("scripts.lib.damage_provenance")
local Sound = require("scripts.lib.sound_volume")
local definitions = require("scripts.entities.definitions")

local M = {}
ConchBlessing.landmine = M

local ID = Isaac.GetItemIdByName("Landmine")
local PROC_KEY = "landmine"
local HIT_KEY = "__ConchBlessingLandmineHit"

M.data = {
    damageMultiplier = 2, -- of the tear's own damage
    blastRadius = 60,     -- a tile and a half, plus each enemy's own size
    triggerRadius = 8,    -- an enemy this close (plus its size) has stepped on it
    armFrames = 8,        -- a mine arms as its Appear animation ends
    maxMines = 10,        -- per player; laying an eleventh removes the oldest
    backtrack = 40,       -- how far back along its flight a tear that died over a wall, rock or pit looks for floor
    floorMargin = 6,      -- a mine stays this far inside the room's floor
    chainDelay = 3,       -- updates before a mine caught in a blast goes off
    blastScale = 0.6,     -- the vanilla bomb explosion is drawn this size
}

local BLAST_COLOR = Color(0.75, 1, 0.6, 1, 0, 0.06, 0) -- Ipecac's green
local BLAST_SOUND = SoundEffect.SOUND_EXPLOSION_WEAK or SoundEffect.SOUND_BOOM

local function effectVariant(entry)
    local found = -1
    if entry and type(Isaac.GetEntityTypeByName) == "function" and type(Isaac.GetEntityVariantByName) == "function" then
        local ok, entityType, value = pcall(function()
            return Isaac.GetEntityTypeByName(entry.name), Isaac.GetEntityVariantByName(entry.name)
        end)
        if ok and entityType == entry.id and type(value) == "number" and value > 0 then found = value end
    end
    if found <= 0 and ID > 0 then
        ConchBlessing.printError("Landmine: the effect '" .. tostring(entry and entry.name)
            .. "' is not registered; restart the game after entities2.xml changes")
    end
    return found
end
local mineVariant = effectVariant(definitions.LANDMINE)

local tearDeath = ModCallbacks.MC_POST_TEAR_DEATH
local tearCollision = ModCallbacks.MC_POST_TEAR_COLLISION
M.available = type(tearDeath) == "number" and type(tearCollision) == "number" and mineVariant > 0

local mines = {} -- in the order they were laid: { ref, owner, damage, fuse }
-- Runtime evidence for cb test landmine; never saved.
local evidence
local function resetEvidence()
    evidence = { deaths = 0, hits = 0, laid = 0, skipped = 0, trimmed = 0, exploded = 0, struck = 0, chained = 0,
        last = nil }
end
resetEvidence()

local function isActingPlayer(player)
    if not player then return false end
    if type(player.IsDead) == "function" and player:IsDead() then return false end
    if type(player.IsCoopGhost) == "function" and player:IsCoopGhost() then return false end
    return true
end

local function samePlayer(a, b)
    return a and b and GetPtrHash(a) == GetPtrHash(b) or false
end

-- ------------------------------------------------------------------ pure rules
-- The blast a mine laid by a tear of `tearDamage` deals to each enemy.
local function mineDamage(tearDamage)
    return M.data.damageMultiplier * math.max(0, tonumber(tearDamage) or 0)
end

-- Whether something `distance` away whose own size is `size` is within `radius`.
local function within(distance, radius, size)
    return distance <= radius + math.max(0, tonumber(size) or 0)
end

-- How many of a player's `count` mines must go before one more is laid.
local function excess(count, cap)
    return math.max(0, (tonumber(count) or 0) - (tonumber(cap) or 0) + 1)
end

-- ------------------------------------------------------------------ placement
local function isFloor(room, position)
    if not room:IsPositionInRoom(position, M.data.floorMargin) then return false end
    return room:GetGridCollisionAtPos(position) == GridCollisionClass.COLLISION_NONE
end

-- The floor spot for a tear that died at `position`: there, or the nearest
-- free floor back along `back` (a unit vector toward where it came from).
local function floorSpot(room, position, back)
    local start = room:GetClampedPosition(position, M.data.floorMargin)
    for step = 0, M.data.backtrack, 4 do
        local spot = start + back * step
        if isFloor(room, spot) then return spot end
    end
    return nil
end

-- ------------------------------------------------------------------ mines
local function ownerOf(record)
    local entity = record and record.owner and record.owner.Ref
    local player = entity and entity:ToPlayer()
    if player and player:Exists() then return player end
    return nil
end

local function liveMine(record)
    local effect = record and record.ref and record.ref.Ref
    if effect and effect:Exists() then return effect end
    return nil
end

local function removeMine(index, poof)
    local record = table.remove(mines, index)
    local effect = liveMine(record)
    if effect then
        if poof then
            local smoke = Isaac.Spawn(EntityType.ENTITY_EFFECT, EffectVariant.POOF01, 0, effect.Position, Vector.Zero, nil)
            if smoke then smoke.SpriteScale = Vector(0.5, 0.5) end
        end
        effect:Remove()
    end
end

local function lay(player, position, damage, snapshot)
    local own = {}
    for index, record in ipairs(mines) do
        if samePlayer(ownerOf(record), player) then own[#own + 1] = index end
    end
    for k = excess(#own, M.data.maxMines), 1, -1 do
        removeMine(own[k], true)
        evidence.trimmed = evidence.trimmed + 1
    end
    local mine = Isaac.Spawn(EntityType.ENTITY_EFFECT, mineVariant, 0, position, Vector.Zero, player)
    mine = mine and mine:ToEffect()
    if not mine then return nil end
    -- Lies on the floor: drawn under anything standing over it.
    mine.DepthOffset = -1000
    mine:GetSprite():Play("Appear", true)
    DamageProvenance.markTriggeredAttack(mine, PROC_KEY, snapshot, PROC_KEY)
    mines[#mines + 1] = { ref = EntityPtr(mine), owner = EntityPtr(player), damage = damage }
    evidence.laid = evidence.laid + 1
    evidence.last = { x = position.X, y = position.Y, damage = damage }
    return mine
end

-- An active enemy standing on the mine, if any (flying ones count too).
local function stepper(effect)
    local reach = M.data.triggerRadius
    for _, entity in ipairs(Isaac.FindInRadius(effect.Position, reach + 80, EntityPartition.ENEMY)) do
        if entity:IsActiveEnemy(false) and not entity:HasEntityFlags(EntityFlag.FLAG_FRIENDLY)
            and within(entity.Position:Distance(effect.Position), reach, entity.Size) then
            return entity
        end
    end
    return nil
end

local function explode(index)
    local record = mines[index]
    local effect = liveMine(record)
    if not effect then
        table.remove(mines, index)
        return
    end
    local position = effect.Position
    local blast = Isaac.Spawn(EntityType.ENTITY_EFFECT, EffectVariant.BOMB_EXPLOSION, 0, position, Vector.Zero, nil)
    if blast then
        blast.SpriteScale = Vector(M.data.blastScale, M.data.blastScale)
        blast.Color = BLAST_COLOR
    end
    if BLAST_SOUND then SFXManager():Play(BLAST_SOUND, Sound.volume(0.8), 0, false, 1.1) end
    local damage, radius, source = mineDamage(record.damage), M.data.blastRadius, EntityRef(effect)
    for _, entity in ipairs(Isaac.FindInRadius(position, radius + 80, EntityPartition.ENEMY)) do
        if entity:IsVulnerableEnemy() and not entity:HasEntityFlags(EntityFlag.FLAG_FRIENDLY)
            and within(entity.Position:Distance(position), radius, entity.Size) then
            entity:TakeDamage(damage, DamageFlag.DAMAGE_EXPLOSION, source, 0)
            evidence.struck = evidence.struck + 1
        end
    end
    for _, other in ipairs(mines) do
        local mine = other ~= record and not other.fuse and liveMine(other)
        if mine and within(mine.Position:Distance(position), radius, 0) then
            other.fuse = M.data.chainDelay
            evidence.chained = evidence.chained + 1
        end
    end
    evidence.exploded = evidence.exploded + 1
    removeMine(index, false)
end

-- ------------------------------------------------------------------ callbacks
-- Every collision a holder's tear really makes with an enemy marks it as a hit.
function M.onTearCollision(_, tear, collider)
    if not collider or not collider:IsEnemy() or collider:HasEntityFlags(EntityFlag.FLAG_FRIENDLY) then return end
    local player = DamageProvenance.getDirectPlayerOwner(tear)
    if player and player:GetCollectibleNum(ID) > 0 then tear:GetData()[HIT_KEY] = true end
end

function M.onTearDeath(_, tear)
    local player = DamageProvenance.getDirectPlayerOwner(tear)
    if not player or ID <= 0 or player:GetCollectibleNum(ID) <= 0 or not isActingPlayer(player) then return end
    evidence.deaths = evidence.deaths + 1
    if tear:GetData()[HIT_KEY] then
        evidence.hits = evidence.hits + 1
        return
    end
    local back = tear.Velocity * -1
    if back:Length() < 0.1 then back = player.Position - tear.Position end
    back = back:Length() > 0 and back:Normalized() or Vector.Zero
    local spot = floorSpot(Game():GetRoom(), tear.Position, back)
    if not spot then
        evidence.skipped = evidence.skipped + 1
        return
    end
    lay(player, spot, tear.CollisionDamage, DamageProvenance.getSnapshot(tear))
end

function M.onUpdate()
    if #mines == 0 then return end
    local index = 1
    while index <= #mines do
        local record = mines[index]
        local effect = liveMine(record)
        if not effect then
            table.remove(mines, index)
        else
            local sprite = effect:GetSprite()
            if sprite:IsFinished("Appear") then sprite:Play("Idle", true) end
            local go
            if record.fuse then
                record.fuse = record.fuse - 1
                go = record.fuse <= 0
            else
                go = effect.FrameCount >= M.data.armFrames and stepper(effect) ~= nil
            end
            if go then explode(index) else index = index + 1 end
        end
    end
end

-- Mines are effects of their room: a new room, game start and exit forget them.
function M.onNewRoom() mines = {} end
function M.onGameStarted() mines = {} end
function M.onGameExit() mines = {} end
function M.onModUnload()
    for index = #mines, 1, -1 do removeMine(index, false) end
end

function M.mines() return mines end
function M.mineVariant() return mineVariant end

M._test = {
    mineDamage = mineDamage,
    within = within,
    excess = excess,
    floorSpot = floorSpot,
    lay = lay,
    explode = explode,
    stepper = stepper,
    evidence = function() return evidence end,
    resetEvidence = resetEvidence,
    procKey = PROC_KEY,
    hitKey = HIT_KEY,
}

-- REPENTOGON's tear callbacks, which the ItemData registrar does not map.
if M.available then
    ConchBlessing:AddCallback(tearCollision, M.onTearCollision)
    ConchBlessing:AddCallback(tearDeath, M.onTearDeath)
else
    ConchBlessing.printDebug("Landmine: REPENTOGON's tear death and collision callbacks are missing; no mines")
end

return M
