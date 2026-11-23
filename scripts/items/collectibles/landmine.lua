local require = ConchBlessingRequire or require -- reloadable loader, see main.lua
-- 지뢰 (Landmine), the Magic Conch's neutral answer to Ipecac (user design
-- 2026-11-15). Ipecac turns every tear into a bomb; this keeps the tears as
-- they are and drops a mine at the holder's feet on every attack they make,
-- enemies about or not (user decisions 2026-11-23 and 11-24: at first only in
-- a room with enemies, which left an empty room's shooting with nothing to
-- show). Mines may lie on top of one
-- another: shooting in place piles them up, and an enemy stepping on the pile
-- sets off every mine in it. Earlier that day a mine dropped every two tiles
-- walked while shooting, never within a tile of another; before that each
-- tear dropped mines along its flight (2026-11-19, after Auri's Blue Eye),
-- which did not feel like mines: strong tears killed the enemies before any
-- reached a mine, and the mines lay where the tears flew rather than where
-- enemies walk. An attack is REPENTOGON's weapon trigger, once per attack
-- whatever the weapon; a familiar's weapon is its own, so its shots lay
-- nothing. Without REPENTOGON each tear the holder fires stands for an
-- attack, so a multishot attack drops several mines and other weapons none.
-- There is no cap (user decision, same day). The mine falls from the
-- holder's hands, lands in a splash of ooze and arms; none is dropped over a
-- wall, rock or pit. An enemy coming onto an armed mine sets it off: every
-- enemy within reach takes twice the damage the holder had when it was laid,
-- and other mines the blast reaches go off a moment later.
--
-- Mines never hurt a player (user decision 2026-11-15). The blast is dealt
-- here, to enemies only, never through the engine's explosion, which would
-- also hit players and break rocks; the vanilla bomb explosion is spawned only
-- as a picture.
--
-- Mines are effects that last as long as their room; nothing is saved.
-- Without a cap a room may hold a hundred mines or more, so they are also
-- filed by floor tile, and arming, stepping and chaining look only at the
-- tiles around a spot; a pile going off draws one explosion.
local DamageProvenance = require("scripts.lib.damage_provenance")
local WeaponAttackTracker = require("scripts.lib.weapon_attack_tracker")
local Sound = require("scripts.lib.sound_volume")
local definitions = require("scripts.entities.definitions")

local M = {}
ConchBlessing.landmine = M

local ID = Isaac.GetItemIdByName("Landmine")
local PROC_KEY = "landmine"

M.data = {
    damageMultiplier = 2, -- of the holder's damage when the mine was laid
    blastRadius = 60,     -- a tile and a half, plus each enemy's own size
    triggerRadius = 8,    -- an enemy this close (plus its size) has stepped on it
    armFrames = 8,        -- a mine arms this many updates after landing, as its Land animation ends
    dropHeight = 20,      -- a mine falls from this high at the holder's feet
    gravity = 1.5,        -- a dropped mine falls this much faster each update
    floorMargin = 6,      -- a mine stays this far inside the room's floor
    chainDelay = 3,       -- updates before a mine caught in a blast goes off
    blastScale = 0.6,     -- the vanilla bomb explosion is drawn this size
    pictureGap = 20,      -- mines this close going off in one update draw one explosion
}

-- REPENTOGON reports each attack (CallbackManager's `weaponFiredOptional`
-- registers it under the same condition); without it the tears stand in.
local WEAPON_EVENT = (function()
    local repentogon = rawget(_G, "REPENTOGON")
    return type(repentogon) == "table" and repentogon.Real == true
        and type(ModCallbacks.MC_POST_TRIGGER_WEAPON_FIRED) == "number"
end)()

local BLAST_COLOR = Color(0.75, 1, 0.6, 1, 0, 0.06, 0) -- Ipecac's green
local BLAST_SOUND = SoundEffect.SOUND_EXPLOSION_WEAK or SoundEffect.SOUND_BOOM
local CELL = 40 -- a floor tile, the size of the filing grid

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

M.available = mineVariant > 0

-- Every mine is a record { ref, owner, damage, x, y, key, lift, fall, landed,
-- landedAt, armed, idle, fuse, going, dead }; `lift` is its height above the
-- floor (negative, as PositionOffset) while it falls. `mines` keeps them in the order they were laid; a record that
-- went is marked dead and left there until the next compaction.
local mines, cells, fresh, fused = {}, {}, {}, {}
local dirty = false     -- some record died since `mines` was last compacted
local soundFrame = -1   -- one blast sound per update however many mines go off
-- The explosions drawn this update ({ x, y }), so a pile draws one.
local pictures, pictureFrame = {}, -1
-- Runtime evidence for cb test landmine; never saved.
local evidence
local function resetEvidence()
    evidence = { laid = 0, landed = 0, blocked = 0, exploded = 0, struck = 0, chained = 0, pictures = 0,
        last = nil }
end
resetEvidence()

local function isActingPlayer(player)
    if not player then return false end
    if type(player.IsDead) == "function" and player:IsDead() then return false end
    if type(player.IsCoopGhost) == "function" and player:IsCoopGhost() then return false end
    return true
end

-- ------------------------------------------------------------------ pure rules
-- The blast a mine laid by a holder of `damage` deals to each enemy.
local function mineDamage(damage)
    return M.data.damageMultiplier * math.max(0, tonumber(damage) or 0)
end

-- Whether something `distance` away whose own size is `size` is within `radius`.
local function within(distance, radius, size)
    return distance <= radius + math.max(0, tonumber(size) or 0)
end

local function tileOf(value) return math.floor(value / CELL) end
local function keyOf(tx, ty) return tx * 4096 + ty end

-- ------------------------------------------------------------------ filing
local function file(record)
    local list = cells[record.key]
    if not list then
        list = {}
        cells[record.key] = list
    end
    list[#list + 1] = record
end

local function unfile(record)
    local list = cells[record.key]
    if not list then return end
    for k = #list, 1, -1 do
        if list[k] == record then
            list[k] = list[#list]
            list[#list] = nil
            break
        end
    end
    if #list == 0 then cells[record.key] = nil end
end

-- Fills `nearby` with every record filed on the tiles within `radius` of
-- (x, y) and returns how many; the caller checks the exact distance.
local nearby = {}
local function gather(x, y, radius)
    local count, reach = 0, math.ceil(radius / CELL)
    local tx, ty = tileOf(x), tileOf(y)
    for i = tx - reach, tx + reach do
        for j = ty - reach, ty + reach do
            local list = cells[keyOf(i, j)]
            if list then
                for k = 1, #list do
                    count = count + 1
                    nearby[count] = list[k]
                end
            end
        end
    end
    return count
end

local function liveMine(record)
    local effect = record and record.ref and record.ref.Ref
    if effect and effect:Exists() then return effect end
    return nil
end

local function drop(record, remove)
    if record.dead then return end
    record.dead = true
    unfile(record)
    dirty = true
    local effect = remove and liveMine(record)
    if effect then effect:Remove() end
end

-- Forgets the records that went; with `checkLive`, also those whose effect
-- something else removed.
local function compact(checkLive)
    if not dirty and not checkLive then return end
    local kept = {}
    for _, record in ipairs(mines) do
        if not record.dead and checkLive and not liveMine(record) then drop(record, false) end
        if not record.dead then kept[#kept + 1] = record end
    end
    mines, dirty = kept, false
end

local function reset()
    mines, cells, fresh, fused, pictures = {}, {}, {}, {}, {}
    dirty, soundFrame, pictureFrame = false, -1, -1
end

-- ------------------------------------------------------------------ placement
local function isFloor(room, position)
    if not room:IsPositionInRoom(position, M.data.floorMargin) then return false end
    return room:GetGridCollisionAtPos(position) == GridCollisionClass.COLLISION_NONE
end

local function land(record, mine)
    record.lift, record.fall, record.landed, record.landedAt = 0, 0, true, mine.FrameCount
    mine.PositionOffset = Vector.Zero
    mine:GetSprite():Play("Land", true)
    evidence.landed = evidence.landed + 1
end

-- A mine for `position` on the floor, dropped from `lift` above it
-- (negative, as PositionOffset) or landing at once.
local function lay(player, position, damage, snapshot, lift)
    local mine = Isaac.Spawn(EntityType.ENTITY_EFFECT, mineVariant, 0, position, Vector.Zero, player)
    mine = mine and mine:ToEffect()
    if not mine then return nil end
    -- Lies on the floor: drawn under anything standing over it.
    mine.DepthOffset = -1000
    DamageProvenance.markTriggeredAttack(mine, PROC_KEY, snapshot, PROC_KEY)
    local x, y = position.X, position.Y
    local record = { ref = EntityPtr(mine), owner = EntityPtr(player), damage = damage, x = x, y = y,
        key = keyOf(tileOf(x), tileOf(y)) }
    lift = math.min(0, tonumber(lift) or 0)
    if lift < -1 then
        record.lift, record.fall = lift, 0
        mine.PositionOffset = Vector(0, lift)
        mine:GetSprite():Play("Fall", true)
    else
        land(record, mine)
    end
    mines[#mines + 1] = record
    fresh[#fresh + 1] = record
    file(record)
    evidence.laid = evidence.laid + 1
    evidence.last = { x = x, y = y, damage = damage, lift = lift }
    return mine, record
end

-- ------------------------------------------------------------------ blasts
-- Whether a blast at (x, y) needs its own picture this update: mines piled
-- on one spot going off together draw one explosion.
local function newPicture(x, y, frame)
    if frame ~= pictureFrame then pictures, pictureFrame = {}, frame end
    local gap = M.data.pictureGap
    for _, other in ipairs(pictures) do
        local dx, dy = other.x - x, other.y - y
        if dx * dx + dy * dy < gap * gap then return false end
    end
    pictures[#pictures + 1] = { x = x, y = y }
    return true
end

local function explode(record)
    local effect = liveMine(record)
    if not effect then
        drop(record, false)
        return
    end
    local position = effect.Position
    local frame = Game():GetFrameCount()
    if newPicture(position.X, position.Y, frame) then
        local blast = Isaac.Spawn(EntityType.ENTITY_EFFECT, EffectVariant.BOMB_EXPLOSION, 0, position, Vector.Zero, nil)
        if blast then
            blast.SpriteScale = Vector(M.data.blastScale, M.data.blastScale)
            blast.Color = BLAST_COLOR
        end
        evidence.pictures = evidence.pictures + 1
    end
    if BLAST_SOUND and frame ~= soundFrame then
        soundFrame = frame
        SFXManager():Play(BLAST_SOUND, Sound.volume(0.8), 0, false, 1.1)
    end
    local damage, radius, source = mineDamage(record.damage), M.data.blastRadius, EntityRef(effect)
    for _, entity in ipairs(Isaac.FindInRadius(position, radius + 80, EntityPartition.ENEMY)) do
        if entity:IsVulnerableEnemy() and not entity:HasEntityFlags(EntityFlag.FLAG_FRIENDLY)
            and within(entity.Position:Distance(position), radius, entity.Size) then
            entity:TakeDamage(damage, DamageFlag.DAMAGE_EXPLOSION, source, 0)
            evidence.struck = evidence.struck + 1
        end
    end
    for k = 1, gather(record.x, record.y, radius) do
        local other = nearby[k]
        if other ~= record and not other.dead and not other.fuse and not other.going then
            local dx, dy = other.x - record.x, other.y - record.y
            if dx * dx + dy * dy <= radius * radius and liveMine(other) then
                other.fuse = M.data.chainDelay
                fused[#fused + 1] = other
                evidence.chained = evidence.chained + 1
            end
        end
    end
    evidence.exploded = evidence.exploded + 1
    drop(record, true)
end

-- Mines not yet settled: a falling one drops toward the floor and lands; a
-- landed one hands Land over to Idle and arms.
local function settleFresh()
    if #fresh == 0 then return end
    local still = {}
    for _, record in ipairs(fresh) do
        local effect = not record.dead and liveMine(record)
        if effect then
            if not record.landed then
                record.fall = record.fall + M.data.gravity
                record.lift = record.lift + record.fall
                if record.lift >= 0 then
                    land(record, effect)
                else
                    effect.PositionOffset = Vector(0, record.lift)
                end
            else
                if not record.idle then
                    local sprite = effect:GetSprite()
                    if sprite:IsFinished("Land") then
                        sprite:Play("Idle", true)
                        record.idle = true
                    end
                end
                if not record.armed and effect.FrameCount - record.landedAt >= M.data.armFrames then
                    record.armed = true
                end
            end
            if not (record.idle and record.armed) then still[#still + 1] = record end
        elseif not record.dead then
            drop(record, false)
        end
    end
    fresh = still
end

local function burnFuses()
    if #fused == 0 then return end
    local ready, still = {}, {}
    for _, record in ipairs(fused) do
        if not record.dead then
            record.fuse = record.fuse - 1
            if record.fuse <= 0 then ready[#ready + 1] = record else still[#still + 1] = record end
        end
    end
    fused = still
    for _, record in ipairs(ready) do explode(record) end
end

-- Every armed mine an active enemy stands on (flying ones count too) goes off.
local stepped = {}
local function stepOn()
    local count, reach = 0, M.data.triggerRadius
    local centre = Game():GetRoom():GetCenterPos()
    for _, entity in ipairs(Isaac.FindInRadius(centre, 4000, EntityPartition.ENEMY)) do
        if entity:IsActiveEnemy(false) and not entity:HasEntityFlags(EntityFlag.FLAG_FRIENDLY) then
            local position = entity.Position
            local x, y = position.X, position.Y
            local radius = reach + math.max(0, tonumber(entity.Size) or 0)
            for k = 1, gather(x, y, radius) do
                local record = nearby[k]
                if record.armed and not record.fuse and not record.going then
                    local dx, dy = record.x - x, record.y - y
                    if dx * dx + dy * dy <= radius * radius then
                        record.going = true
                        count = count + 1
                        stepped[count] = record
                    end
                end
            end
        end
    end
    for k = 1, count do
        local record = stepped[k]
        stepped[k] = nil
        explode(record)
    end
end

-- ------------------------------------------------------------------ callbacks
-- An attack by `player`: a holder drops a mine at their feet over free floor,
-- on top of any mine already there.
local function attack(player)
    if not M.available or ID <= 0 or not player or player:GetCollectibleNum(ID) <= 0 then return end
    if not isActingPlayer(player) then return end
    local room = Game():GetRoom()
    local position = player.Position
    if not isFloor(room, position) then
        evidence.blocked = evidence.blocked + 1
        return
    end
    lay(player, position, player.Damage, nil, -M.data.dropHeight)
end

-- REPENTOGON: one weapon trigger is one attack, whatever the weapon; only a
-- player's own weapon counts, never a familiar's.
function M.onWeaponFired(_, _, _, owner)
    attack(WeaponAttackTracker.getDirectPlayerOwner(owner))
end

-- Without REPENTOGON each tear the holder fires stands for an attack.
function M.onFireTear(_, tear)
    if WEAPON_EVENT or not tear then return end
    local spawner = tear.SpawnerEntity
    attack(spawner and spawner:ToPlayer())
end

function M.onUpdate()
    if #mines == 0 then return end
    compact(false)
    settleFresh()
    burnFuses()
    if #mines > 0 then stepOn() end
end

-- Mines are effects of their room: a new room, game start and exit forget them.
function M.onNewRoom() reset() end
function M.onGameStarted() reset() end
function M.onGameExit() reset() end
function M.onModUnload()
    for _, record in ipairs(mines) do drop(record, true) end
    reset()
end

-- The live mines in the order they were laid.
function M.mines()
    compact(true)
    return mines
end
function M.mineVariant() return mineVariant end

M._test = {
    mineDamage = mineDamage,
    within = within,
    isFloor = isFloor,
    attack = attack,
    lay = lay,
    land = land,
    explode = explode,
    tiles = function() return cells end,
    evidence = function() return evidence end,
    resetEvidence = resetEvidence,
    weaponEvent = function() return WEAPON_EVENT end,
    procKey = PROC_KEY,
}

if not M.available then
    ConchBlessing.printDebug("Landmine: its mine effect is not registered; no mines")
end

return M
