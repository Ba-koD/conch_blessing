local require = ConchBlessingRequire or require -- reloadable loader, see main.lua
-- 지뢰 (Landmine), the Magic Conch's neutral answer to Ipecac (user design
-- 2026-11-15, reworked on 2026-11-25 into a tear that sows mines). Ipecac's
-- stat changes are turned round: +40 flat range, a x0.33 damage multiplier,
-- -0.2 tears, and the holder's attacks are locked to tears (REPENTOGON).
-- Every tear the holder fires carries 3 mines, one more for every 5 luck with
-- no upper limit, and scatters them to either side as it flies, one every two
-- tiles; ground that already holds a mine is passed over and the mine carried
-- on. Where the tear stops (an enemy, a wall, the floor) what it still carries
-- spills out around it. A mine landing on an enemy goes off at once; the
-- others lie until something steps on them, an enemy or a player, and a
-- player who sets one off takes no damage (user decision 2026-11-25). The user
-- wants no caps of any kind ("상한은 따로두지마"): mines stay until stepped on
-- however many there are, and a spill with no free ground left piles up.
-- A blast deals every enemy within reach half the damage the holder had when
-- the tear was fired (user decision 2026-11-25, it was twice), and other mines
-- it reaches go off a moment later.
--
-- Earlier forms (kept for the reasons the design moved on): a mine at the
-- feet on every attack (2026-11-23/24), which never felt like sowing mines;
-- before that tears dropped mines along their flight with nothing changed
-- about the tears (2026-11-19), when strong tears killed everything before a
-- mine was reached. The x0.33 damage moves the item's strength into the mines.
--
-- The blast is dealt here, to enemies only, never through the engine's
-- explosion, which would also hit players and break rocks; the vanilla bomb
-- explosion is spawned only as a picture.
--
-- Mines last as long as their room; nothing is saved but StatsAPI's damage
-- multiplier. A room may hold a thousand mines or more, so a mine is no entity
-- of its own: it is a record here, and one effect per room (the "field", drawn
-- before every other entity) draws them all from a few static sprites, one per
-- animation frame. Measured 2026-11-25 with `cb test landmine headroom_compare`:
-- 228 mines as entities of their own cost 4.19 ms of each frame (every mod's
-- per-effect callbacks ran for each), drawn by the field 0.88 ms. Mines are
-- filed by floor tile,
-- and arming, stepping and chaining look only at the tiles around a spot;
-- mines going off together on one spot draw one explosion. A blast's source is
-- the mine's owner, marked with the landmine proc so it never triggers itself.
local DamageProvenance = require("scripts.lib.damage_provenance")
local Sound = require("scripts.lib.sound_volume")
local definitions = require("scripts.entities.definitions")

local M = {}
ConchBlessing.landmine = M

local ID = Isaac.GetItemIdByName("Landmine")
local PROC_KEY = "landmine"

M.data = {
    damageMultiplier = 0.5, -- a blast, of the holder's damage when the tear was fired
    statMultiplier = 0.33, -- the holder's damage multiplier (StatsAPI)
    tears = -0.2,         -- shots a second
    range = 40 * 40,      -- +40 tiles, in TearRange units
    mines = 3,            -- mines a tear carries
    luckStep = 5,         -- one more for every this much luck, with no upper limit
    dropEvery = 80,       -- a tear drops a mine every two tiles flown, the first after one
    scatter = 40,         -- a mine is flung up to a tile to either side
    ahead = { 8, 36 },    -- and this far ahead of the tear
    spill = { 10, 40 },   -- what a stopped tear still carries spills this far around it
    gap = 26,             -- a free spot has no other mine this close
    tries = 6,            -- spots tried for one mine
    flight = 10,          -- updates a mine flies from the tear to the floor
    gravity = 0.9,        -- its fall speeds up this much each update
    landOn = 6,           -- landing this close to an enemy (plus its size) sets it off at once
    blastRadius = 40,     -- a tile, plus each enemy's own size
    triggerRadius = 8,    -- something this close (plus its size) has stepped on it
    armFrames = 8,        -- a landed mine arms this many updates later, as its Land animation ends
    floorMargin = 6,      -- a mine stays this far inside the room's floor
    chainDelay = 3,       -- updates before a mine caught in a blast goes off
    blastScale = 0.45,    -- the vanilla bomb explosion is drawn this size
    pictureGap = 20,      -- mines this close going off in one update draw one explosion
}

local BLAST_COLOR = Color(0.75, 1, 0.6, 1, 0, 0.06, 0) -- Ipecac's green
local BLAST_SOUND = SoundEffect.SOUND_EXPLOSION_WEAK or SoundEffect.SOUND_BOOM
local CELL = 40 -- a floor tile, the size of the filing grid
local WEAPON_CACHE = CacheFlag and CacheFlag.CACHE_WEAPON or nil
local TEARS_WEAPON = WeaponType and WeaponType.WEAPON_TEARS or nil
-- Every primary weapon that replaces the tears. The active items' own weapons
-- (Notched Axe, Urn of Souls) stay theirs.
local OTHER_WEAPONS = {}
for _, name in ipairs({ "WEAPON_BRIMSTONE", "WEAPON_LASER", "WEAPON_KNIFE", "WEAPON_BOMBS", "WEAPON_ROCKETS",
    "WEAPON_MONSTROS_LUNGS", "WEAPON_LUDOVICO_TECHNIQUE", "WEAPON_TECH_X", "WEAPON_BONE", "WEAPON_SPIRIT_SWORD",
    "WEAPON_FETUS", "WEAPON_UMBILICAL_WHIP" }) do
    local value = WeaponType and WeaponType[name]
    if type(value) == "number" then OTHER_WEAPONS[#OTHER_WEAPONS + 1] = value end
end

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

-- The mine's sheet, and the frames of its animations: Fall (in the air), Land
-- (on the way down into its splash) and Idle (its button blinking).
local SHEET = "gfx/" .. (definitions.LANDMINE and definitions.LANDMINE.anm2path or "effects/conch_landmine.anm2")
local FRAMES = { Fall = 1, Land = 8, Idle = 30 }
local FIELD_DEPTH = -100000 -- the field draws before every other entity

-- Every mine is a record { owner, damage, x, y, spot, key, frame, flying,
-- landed, landedAt, idle, idleAt, armed, fuse, going, dead }; (x, y) = spot is
-- where it lands, its place from the moment it is flung. A flying one also
-- keeps { sx, sy, px, py, z, lift, vz, k }: it flies from (sx, sy) at `lift`
-- above the floor (negative, screen pixels as PositionOffset), is drawn at
-- (px, py) raised by z, and lands after `flight` updates. `mines` keeps them
-- in the order they were laid; a record that went is marked dead and left
-- there until the next compaction.
local mines, cells, fresh, fused = {}, {}, {}, {}
-- The room's field effect (EntityPtr), and one static sprite per frame of
-- each animation ({ Fall = { s0 }, Land = { s0 .. s7 }, Idle = { ... } }),
-- false once loading failed.
local field, frames
-- Whether a blast is striking right now (the bench reads it).
local blasting = false
-- The render offset the mines were last drawn with, and a stamp that changes
-- with it (a mine's kept place is good while its stamp matches).
local drawX, drawY, drawStamp = nil, nil, 0
-- Every tear still carrying mines: { ref, owner, damage, load, travel, rng, x,
-- y, vx, vy, lift }, (x, y) and the velocity as last seen.
local carriers = {}
local dirty = false     -- some record died since `mines` was last compacted
local soundFrame = -1   -- one blast sound per update however many mines go off
-- The explosions drawn this update ({ x, y }), so a pile draws one.
local pictures, pictureFrame = {}, -1
-- Whether each player (GetPtrHash) held the item when last seen; `sweep`
-- looks at every player again once after a start or reload.
local holding, sweep = {}, true
-- Runtime evidence for cb test landmine; never saved.
local evidence
local function resetEvidence()
    evidence = { fired = 0, laid = 0, flung = 0, spilled = 0, piled = 0, lost = 0, carried = 0, landed = 0,
        landedOn = 0, exploded = 0, struck = 0, chained = 0, pictures = 0, byPlayer = 0, drawn = 0,
        drawnMines = 0, last = nil }
end
resetEvidence()

local function isActingPlayer(player)
    if not player then return false end
    if type(player.IsDead) == "function" and player:IsDead() then return false end
    if type(player.IsCoopGhost) == "function" and player:IsCoopGhost() then return false end
    return true
end

-- ------------------------------------------------------------------ pure rules
-- The blast a mine from a holder of `damage` deals to each enemy.
local function mineDamage(damage)
    return M.data.damageMultiplier * math.max(0, tonumber(damage) or 0)
end

-- The mines a tear carries at `luck`: 3, one more for every 5, no upper limit.
local function payload(luck)
    luck = math.max(0, tonumber(luck) or 0)
    return M.data.mines + math.floor(luck / M.data.luckStep)
end

-- Whether something `distance` away whose own size is `size` is within `radius`.
local function within(distance, radius, size)
    return distance <= radius + math.max(0, tonumber(size) or 0)
end

-- The upward speed that brings a mine from `lift` (negative) to the floor in
-- `updates` under `gravity`.
local function launchSpeed(lift, updates, gravity)
    return (-lift - 0.5 * gravity * updates * updates) / updates
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

-- Whether no mine (flying or landed) has (x, y) within `gap`.
local function freeSpot(x, y)
    local gap = M.data.gap
    for k = 1, gather(x, y, gap) do
        local other = nearby[k]
        if not other.dead then
            local dx, dy = other.x - x, other.y - y
            if dx * dx + dy * dy < gap * gap then return false end
        end
    end
    return true
end

local function drop(record)
    if record.dead then return end
    record.dead = true
    unfile(record)
    dirty = true
end

-- Forgets the records that went.
local function compact()
    if not dirty then return end
    local kept = {}
    for _, record in ipairs(mines) do
        if not record.dead then kept[#kept + 1] = record end
    end
    mines, dirty = kept, false
end

-- ------------------------------------------------------------------ the field
local function fieldEntity()
    local effect = field and field.Ref
    if effect and effect:Exists() then return effect end
    return nil
end

local function removeField()
    local effect = fieldEntity()
    if effect then effect:Remove() end
    field = nil
end

-- The room's one field effect, spawned with the first mine and kept on the
-- first player (where the camera looks), drawn before everything else.
local function keepField()
    local player = Isaac.GetPlayer(0)
    local at = player and player.Position or Game():GetRoom():GetCenterPos()
    local effect = fieldEntity()
    if not effect then
        effect = Isaac.Spawn(EntityType.ENTITY_EFFECT, mineVariant, 0, at, Vector.Zero, nil)
        effect = effect and effect:ToEffect()
        if not effect then return end
        effect.DepthOffset = FIELD_DEPTH
        effect.Color = Color(1, 1, 1, 0) -- its own picture stays unseen; it draws the mines
        field = EntityPtr(effect)
    end
    effect.Position, effect.Velocity = at, Vector.Zero
end

-- One static sprite per frame of each animation, loaded on the first draw.
local function frameSprites()
    if frames ~= nil then return frames or nil end
    local ok, built = pcall(function()
        local set = {}
        for name, count in pairs(FRAMES) do
            set[name] = {}
            for f = 0, count - 1 do
                local sprite = Sprite()
                sprite:Load(SHEET, true)
                sprite:SetFrame(name, f)
                set[name][f + 1] = sprite
            end
        end
        if type(set.Fall[1].IsLoaded) == "function" and not set.Fall[1]:IsLoaded() then error("sheet not loaded") end
        return set
    end)
    if not ok then
        ConchBlessing.printError("Landmine: could not load " .. SHEET .. ": " .. tostring(built))
        frames = false
        return nil
    end
    frames = built
    return built
end

local function isReflectionPass()
    local room = Game():GetRoom()
    return RenderMode ~= nil and type(room.GetRenderMode) == "function"
        and room:GetRenderMode() == RenderMode.RENDER_WATER_REFLECT
end

local function reset()
    removeField()
    mines, cells, fresh, fused, pictures, carriers = {}, {}, {}, {}, {}, {}
    dirty, soundFrame, pictureFrame, blasting = false, -1, -1, false
end

-- ------------------------------------------------------------------ placement
local function isFloor(room, position)
    if not room:IsPositionInRoom(position, M.data.floorMargin) then return false end
    return room:GetGridCollisionAtPos(position) == GridCollisionClass.COLLISION_NONE
end

local function land(record)
    record.flying, record.landed, record.landedAt = false, true, Game():GetFrameCount()
    record.px, record.py, record.z = record.x, record.y, 0
    evidence.landed = evidence.landed + 1
end

-- A mine of `player` for `to` on the floor: flung from `from` at `lift` above
-- the floor (negative, screen pixels as PositionOffset), or landing at once
-- without them. Returns its record.
local function lay(player, to, damage, from, lift)
    if not M.available then return nil end
    local x, y = to.X, to.Y
    local record = { owner = player and EntityPtr(player) or nil, damage = damage, x = x, y = y,
        spot = Vector(x, y), key = keyOf(tileOf(x), tileOf(y)), frame = Game():GetFrameCount() }
    lift = math.min(0, tonumber(lift) or 0)
    if from then
        record.flying, record.sx, record.sy, record.lift, record.k = true, from.X, from.Y, lift, 0
        record.px, record.py, record.z = from.X, from.Y, lift
        record.vz = launchSpeed(lift, M.data.flight, M.data.gravity)
    else
        land(record)
    end
    mines[#mines + 1] = record
    fresh[#fresh + 1] = record
    file(record)
    keepField()
    evidence.laid = evidence.laid + 1
    evidence.last = { x = x, y = y, damage = damage }
    return record
end

local function carrierPlayer(carrier)
    local entity = carrier.owner and carrier.owner.Ref
    return entity and entity:ToPlayer() or nil
end

-- A mine flung from the flying tear to one side and a little ahead, onto free
-- floor; false when no spot tried is free (the tear carries it on).
local function fling(carrier)
    local room, d = Game():GetRoom(), M.data
    local speed = math.sqrt(carrier.vx * carrier.vx + carrier.vy * carrier.vy)
    if speed <= 0 then return false end
    local ux, uy = carrier.vx / speed, carrier.vy / speed
    local rng = carrier.rng
    for _ = 1, d.tries do
        local side = rng:RandomFloat() < 0.5 and -1 or 1
        local lateral = side * (0.15 + 0.85 * rng:RandomFloat()) * d.scatter
        local ahead = d.ahead[1] + (d.ahead[2] - d.ahead[1]) * rng:RandomFloat()
        local to = Vector(carrier.x + ux * ahead - uy * lateral, carrier.y + uy * ahead + ux * lateral)
        if isFloor(room, to) and freeSpot(to.X, to.Y) then
            lay(carrierPlayer(carrier), to, carrier.damage, Vector(carrier.x, carrier.y), carrier.lift)
            evidence.flung = evidence.flung + 1
            return true
        end
    end
    return false
end

-- What a stopped tear still carries spills around where it stopped. Every
-- mine finds floor if it can: free ground first, else the last floor spot
-- tried, on top of what lies there (no cap, user decision 2026-11-25).
local function spill(carrier)
    if carrier.load <= 0 then return end
    local room, d = Game():GetRoom(), M.data
    local stop = Vector(carrier.x + carrier.vx, carrier.y + carrier.vy)
    if type(room.GetClampedPosition) == "function" then stop = room:GetClampedPosition(stop, d.floorMargin) end
    local rng = carrier.rng
    for _ = 1, carrier.load do
        local free, floor
        for _ = 1, d.tries do
            local angle = rng:RandomFloat() * 2 * math.pi
            local distance = d.spill[1] + (d.spill[2] - d.spill[1]) * rng:RandomFloat()
            local to = Vector(stop.X + math.cos(angle) * distance, stop.Y + math.sin(angle) * distance)
            if isFloor(room, to) then
                floor = to
                if freeSpot(to.X, to.Y) then
                    free = to
                    break
                end
            end
        end
        local to = free or floor
        if to then
            lay(carrierPlayer(carrier), to, carrier.damage, Vector(carrier.x, carrier.y), carrier.lift)
            evidence.spilled = evidence.spilled + 1
            if not free then evidence.piled = evidence.piled + 1 end
        else
            evidence.lost = evidence.lost + 1
        end
    end
    carrier.load = 0
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

-- Every vulnerable, unfriendly enemy within `radius` (plus its size) of
-- `position` takes `damage` from `source`.
local function strike(position, radius, damage, source)
    blasting = true
    for _, entity in ipairs(Isaac.FindInRadius(position, radius + 80, EntityPartition.ENEMY)) do
        if entity:IsVulnerableEnemy() and not entity:HasEntityFlags(EntityFlag.FLAG_FRIENDLY)
            and within(entity.Position:Distance(position), radius, entity.Size) then
            entity:TakeDamage(damage, DamageFlag.DAMAGE_EXPLOSION, source, 0)
            evidence.struck = evidence.struck + 1
        end
    end
    blasting = false
end

local function explode(record)
    if record.dead then return end
    local position = record.spot
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
    local damage, radius = mineDamage(record.damage), M.data.blastRadius
    -- The owner is the source, marked with this proc so the blast's hits
    -- never set off mines again through it; a mine whose owner left the run
    -- strikes with no source.
    local owner = record.owner and record.owner.Ref
    owner = owner and owner:Exists() and owner:ToPlayer() or nil
    if owner then
        DamageProvenance.withTriggeredSource(owner, PROC_KEY, nil, PROC_KEY, function()
            strike(position, radius, damage, EntityRef(owner))
        end)
    else
        strike(position, radius, damage, EntityRef(nil))
    end
    for k = 1, gather(record.x, record.y, radius) do
        local other = nearby[k]
        if other ~= record and other.landed and not other.dead and not other.fuse and not other.going then
            local dx, dy = other.x - record.x, other.y - record.y
            if dx * dx + dy * dy <= radius * radius then
                other.fuse = M.data.chainDelay
                fused[#fused + 1] = other
                evidence.chained = evidence.chained + 1
            end
        end
    end
    evidence.exploded = evidence.exploded + 1
    drop(record)
end

-- Whether an active enemy is within `reach` (plus its size) of (x, y).
local function enemyAt(x, y, reach)
    local spot = Vector(x, y)
    for _, entity in ipairs(Isaac.FindInRadius(spot, reach + 80, EntityPartition.ENEMY)) do
        if entity:IsActiveEnemy(false) and not entity:HasEntityFlags(EntityFlag.FLAG_FRIENDLY)
            and within(entity.Position:Distance(spot), reach, entity.Size) then
            return true
        end
    end
    return false
end

-- Mines not yet settled: a flying one flies on toward its spot and lands,
-- going off at once on an enemy; a landed one hands Land over to Idle and
-- arms.
local function settleFresh()
    if #fresh == 0 then return end
    local still, onEnemy = {}, nil
    local d, now = M.data, Game():GetFrameCount()
    for _, record in ipairs(fresh) do
        if record.dead then
            -- gone (a blast): nothing to settle
        elseif record.frame == now then
            -- Laid this update: it starts its flight on the next one.
            still[#still + 1] = record
        else
            if record.flying then
                record.k = record.k + 1
                local k = record.k
                if k >= d.flight then
                    land(record)
                    if enemyAt(record.x, record.y, d.landOn) then
                        record.going = true
                        onEnemy = onEnemy or {}
                        onEnemy[#onEnemy + 1] = record
                        evidence.landedOn = evidence.landedOn + 1
                    end
                else
                    local f = k / d.flight
                    record.px = record.sx + (record.x - record.sx) * f
                    record.py = record.sy + (record.y - record.sy) * f
                    record.z = math.min(0, record.lift + record.vz * k + 0.5 * d.gravity * k * k)
                end
            else
                local age = now - record.landedAt
                if not record.idle and age >= FRAMES.Land then
                    record.idle, record.idleAt = true, now
                end
                if not record.armed and age >= d.armFrames then record.armed = true end
            end
            if not (record.idle and record.armed) and not record.going then still[#still + 1] = record end
        end
    end
    fresh = still
    if onEnemy then
        for _, record in ipairs(onEnemy) do explode(record) end
    end
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

-- Every armed mine something stands on goes off: an active enemy (flying ones
-- too) or a living player, who takes no damage from it.
local stepped = {}
local function stepOn()
    local count, reach = 0, M.data.triggerRadius
    local function standing(entity, byPlayer)
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
                    if byPlayer then evidence.byPlayer = evidence.byPlayer + 1 end
                end
            end
        end
    end
    local game = Game()
    local centre = game:GetRoom():GetCenterPos()
    for _, entity in ipairs(Isaac.FindInRadius(centre, 4000, EntityPartition.ENEMY)) do
        if entity:IsActiveEnemy(false) and not entity:HasEntityFlags(EntityFlag.FLAG_FRIENDLY) then
            standing(entity, false)
        end
    end
    for i = 0, game:GetNumPlayers() - 1 do
        local player = Isaac.GetPlayer(i)
        if isActingPlayer(player) then standing(player, true) end
    end
    for k = 1, count do
        local record = stepped[k]
        stepped[k] = nil
        explode(record)
    end
end

-- Every tear still carrying mines: one flying on drops one each two tiles,
-- one that stopped spills the rest.
local function carry()
    local still = {}
    local every = M.data.dropEvery
    for _, carrier in ipairs(carriers) do
        local tear = carrier.ref.Ref
        if tear and tear:Exists() then
            local position, velocity = tear.Position, tear.Velocity
            local dx, dy = position.X - carrier.x, position.Y - carrier.y
            carrier.x, carrier.y, carrier.vx, carrier.vy = position.X, position.Y, velocity.X, velocity.Y
            carrier.lift = math.min(0, tonumber(tear.Height) or carrier.lift)
            carrier.travel = carrier.travel - math.sqrt(dx * dx + dy * dy)
            if carrier.travel <= 0 then
                if fling(carrier) then
                    carrier.load = carrier.load - 1
                    carrier.travel = carrier.travel + every
                else
                    evidence.carried = evidence.carried + 1
                end
            end
            if carrier.load > 0 then still[#still + 1] = carrier end
        else
            spill(carrier)
        end
    end
    carriers = still
end

-- ------------------------------------------------------------------ stats
local STAT_FLAGS = CacheFlag.CACHE_DAMAGE | CacheFlag.CACHE_FIREDELAY | CacheFlag.CACHE_RANGE | (WEAPON_CACHE or 0)

-- The x0.33 damage multiplier is StatsAPI's item multiplier, kept in step with
-- whether the player holds the item (copies do not stack).
local function syncMultiplier(player, held)
    local um = ConchBlessing.stats and ConchBlessing.stats.unifiedMultipliers
    if not um or type(um.SetItemMultiplier) ~= "function" then return end
    local state = ConchBlessing.getUnifiedMultiplierState and ConchBlessing.getUnifiedMultiplierState(player, um)
    local row = state and state.itemMultipliers and state.itemMultipliers[ID]
    local entry = row and row.Damage
    local target = held and M.data.statMultiplier or nil
    if target and (not entry or entry.value ~= target) then
        um:SetItemMultiplier(player, ID, "Damage", target, "Landmine")
    elseif not target and entry then
        um:RemoveItemMultiplier(player, ID, "Damage")
    else
        return
    end
    if um.QueueCacheUpdate then um:QueueCacheUpdate(player, "Damage") end
    if um.SaveToSaveManager then um:SaveToSaveManager(player) end
end

-- When a player gains or loses the item, its multiplier follows and their
-- stats and weapons are evaluated again (the items.xml cache flags do the
-- same on a pickup; this also covers a removal the engine does not report).
local function syncHolder(player)
    local hash = GetPtrHash(player)
    local held = player:GetCollectibleNum(ID) > 0
    local was = holding[hash]
    if was == held and not sweep then return end
    holding[hash] = held
    syncMultiplier(player, held)
    if was ~= nil or held then
        player:AddCacheFlags(STAT_FLAGS)
        player:EvaluateItems()
    end
end

-- Locks a holder's attacks to tears inside their own weapon cache evaluation
-- (REPENTOGON); the next evaluation without the item rebuilds the weapons.
local function lockTears(player)
    if type(player.EnableWeaponType) ~= "function" or type(TEARS_WEAPON) ~= "number" then return false end
    for _, weapon in ipairs(OTHER_WEAPONS) do player:EnableWeaponType(weapon, false) end
    player:EnableWeaponType(TEARS_WEAPON, true)
    return true
end

-- ------------------------------------------------------------------ callbacks
function M.onEvaluateCache(_, player, flag)
    if ID <= 0 or not player or player:GetCollectibleNum(ID) <= 0 then return end
    local stats = ConchBlessing.stats
    if flag == CacheFlag.CACHE_FIREDELAY then
        if stats and stats.tears and stats.tears.applyAddition then stats.tears.applyAddition(player, M.data.tears, nil) end
    elseif flag == CacheFlag.CACHE_RANGE then
        if stats and stats.range and stats.range.applyAddition then stats.range.applyAddition(player, M.data.range, nil) end
    elseif WEAPON_CACHE and flag == WEAPON_CACHE then
        lockTears(player)
    end
end

-- Every tear a living holder fires carries its mines (familiars' tears are
-- their own and carry none).
function M.onFireTear(_, tear)
    if not M.available or ID <= 0 or not tear then return end
    local spawner = tear.SpawnerEntity
    local player = spawner and spawner:ToPlayer()
    if not player or player:GetCollectibleNum(ID) <= 0 or not isActingPlayer(player) then return end
    local rng = RNG()
    rng:SetSeed(math.max(1, tear.InitSeed or 1), 35)
    local position, velocity = tear.Position, tear.Velocity
    carriers[#carriers + 1] = { ref = EntityPtr(tear), owner = EntityPtr(player), damage = player.Damage,
        load = payload(player.Luck), travel = M.data.dropEvery / 2, rng = rng, x = position.X, y = position.Y,
        vx = velocity.X, vy = velocity.Y, lift = math.min(0, tonumber(tear.Height) or 0) }
    evidence.fired = evidence.fired + 1
end

function M.onUpdate()
    if ID > 0 then
        local game = Game()
        for i = 0, game:GetNumPlayers() - 1 do
            local player = Isaac.GetPlayer(i)
            if player then syncHolder(player) end
        end
        sweep = false
    end
    if #carriers > 0 then carry() end
    if #mines == 0 then return end
    compact()
    settleFresh()
    burnFuses()
    if #mines > 0 then stepOn() end
    compact()
    if #mines > 0 then keepField() else removeField() end
end

-- The field draws every mine: a flying one in the air, a landing one on its
-- frame of Land, a lying one on its frame of Idle (from when it began).
function M.onFieldRender(_, effect, offset)
    local own = fieldEntity()
    if not own or GetPtrHash(effect) ~= GetPtrHash(own) or #mines == 0 or isReflectionPass() then return end
    local set = frameSprites()
    if not set then return end
    offset = offset or Vector.Zero
    local now = Game():GetFrameCount()
    local fall, land, idle = set.Fall[1], set.Land, set.Idle
    local landCount, idleCount = FRAMES.Land, FRAMES.Idle
    -- A lying mine's place on the render plane never moves, and the offset
    -- (the camera and the shake) seldom does, so each mine keeps where it was
    -- last drawn and works it out again only when the offset changed: a
    -- thousand mines make no new Vector a frame (each one is garbage to
    -- collect, which cost more than the drawing; measured 2026-11-25).
    local ox, oy = offset.X, offset.Y
    if ox ~= drawX or oy ~= drawY then drawX, drawY, drawStamp = ox, oy, drawStamp + 1 end
    local stamp = drawStamp
    local drew = 0
    local toRender = Isaac.WorldToRenderPosition
    for k = 1, #mines do
        local r = mines[k]
        if not r.dead then
            drew = drew + 1
            if r.flying then
                fall:Render(toRender(Vector(r.px, r.py)) + offset + Vector(0, r.z))
            else
                local at = r.drawAt
                if r.drawStamp ~= stamp then
                    at = toRender(r.spot) + offset
                    r.drawAt, r.drawStamp = at, stamp
                end
                if r.idle then
                    idle[(now - r.idleAt) % idleCount + 1]:Render(at)
                else
                    land[math.max(0, math.min(landCount - 1, now - r.landedAt)) + 1]:Render(at)
                end
            end
        end
    end
    evidence.drawn, evidence.drawnMines = evidence.drawn + 1, drew
end

if ModCallbacks and ModCallbacks.MC_POST_EFFECT_RENDER and mineVariant > 0 then
    ConchBlessing:AddCallback(ModCallbacks.MC_POST_EFFECT_RENDER, M.onFieldRender, mineVariant)
end

-- Mines belong to their room: a new room, game start and exit forget them.
function M.onNewRoom() reset() end
function M.onGameStarted()
    reset()
    holding, sweep = {}, true
end
function M.onGameExit() reset() end
function M.onModUnload() reset() end

-- The live mines in the order they were laid.
function M.mines()
    compact()
    return mines
end
function M.mineVariant() return mineVariant end

M._test = {
    mineDamage = mineDamage,
    payload = payload,
    within = within,
    launchSpeed = launchSpeed,
    isFloor = isFloor,
    freeSpot = freeSpot,
    lay = lay,
    land = land,
    explode = explode,
    lockTears = lockTears,
    otherWeapons = function() return OTHER_WEAPONS end,
    carriers = function() return carriers end,
    tiles = function() return cells end,
    blasting = function() return blasting end,
    field = fieldEntity,
    clear = reset,
    frames = FRAMES,
    evidence = function() return evidence end,
    resetEvidence = resetEvidence,
    procKey = PROC_KEY,
}

if not M.available then
    ConchBlessing.printDebug("Landmine: its mine effect is not registered; no mines")
end

return M
