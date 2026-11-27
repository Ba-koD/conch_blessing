local require = ConchBlessingRequire or require -- reloadable loader, see main.lua
-- 지뢰 (Landmine), the Magic Conch's neutral answer to Ipecac (user design
-- 2026-11-15, reworked on 2026-11-25 into a tear that sows mines). Ipecac's
-- stat changes are turned round: +40 flat range, a x0.33 damage multiplier,
-- -0.2 tears, and the holder's attacks are locked to tears (REPENTOGON).
-- Every tear of a living holder, whatever made it (fired, split, a tear of
-- that tear's, another mod's), lays mines 3 times, once more for every 5 luck
-- with no upper limit, every 0.2 s while it lives: one mine a time with one
-- copy (alternating sides), a pair with two, three with three, so copies raise
-- both the mines laid at once and the most a tear holds while luck raises only
-- the most (user decision 2026-11-27). Ground that already holds a mine is
-- passed over and the mines tried again on the next update. From the first
-- mine a tear lays out of a full stock it waits 5 fire
-- intervals (5 x (MaxFireDelay + 1) updates) and holds them all again, so a
-- long-lived tear (Ludovico, bouncing, orbiting, hovering) keeps sowing (user
-- design 2026-11-27, chosen over a fixed or luck-scaled period in
-- docs/previews/landmine/feel-preview.html). Where the tear stops (an enemy, a
-- wall, the floor) what it still holds spills out around it. A mine landing on
-- an enemy goes off at once; the
-- others lie until something steps on them, an enemy or a player, and a
-- player who sets one off takes no damage (user decision 2026-11-25). The user
-- wants no caps of any kind ("상한은 따로두지마"): mines stay until stepped on
-- however many there are, and a spill with no free ground left piles up.
-- A blast deals every enemy within reach the damage the holder had when the
-- tear was fired (user decision 2026-11-27: half since 2026-11-25 left one
-- copy weaker than no item against a boss; it was twice before that), and
-- other mines it reaches go off a moment later.
--
-- Earlier forms (kept for the reasons the design moved on): a tear fired by
-- the player carried 3 mines and flung one every two tiles (2026-11-25), which
-- gave nothing to tears that live long or are made by other items; a mine at the
-- feet on every attack (2026-11-23/24), which never felt like sowing mines;
-- before that tears dropped mines along their flight with nothing changed
-- about the tears (2026-11-19), when strong tears killed everything before a
-- mine was reached. The x0.33 damage moves the item's strength into the mines.
--
-- The blast is a fake explosion (user decision 2026-11-27): the engine's own
-- explosion, as a real bomb or as Game():BombExplosionEffects, breaks rocks,
-- poop and TNT and opens secret walls, with no callback to stop it (measured
-- that day with `cb test landmine bomb_probe` .. `bomb_probe6`), so the vanilla
-- explosion is spawned only as a picture and the holder's bomb flags are
-- carried by parts that leave the grid alone: Game():BombDamage at each enemy's
-- own spot with radius 1 (damage, burn, poison, slowing, confusion; a rock
-- beside the enemy stays, one under a flying enemy would not, so that enemy is
-- struck plainly), Game():BombTearflagEffects at the mine (Sad Bombs' tears,
-- Sticky and Butt Bombs), and parts made here because neither carries them or
-- the user wanted them otherwise: Bomber Boy's cross (two more blasts along
-- each arm), Scatter Bombs (four small blasts a moment later), Brimstone Bombs
-- (four short Brimstone beams of our own, as long as the blast reaches, in
-- place of the engine's beams across the room) and Ghost Bombs (the engine's
-- Purgatory soul, 인's 창귀, which flies at an enemy and bursts on it, in place
-- of its hungry soul; user decisions 2026-11-27), handed to 인's own soul
-- handling so its burst deals each enemy one hit of half the mine's damage
-- instead of the engine's ticks of twice the holder's. With the homing flag
-- (Bobby-Bomb) a lying mine stands up on legs and creeps toward the nearest
-- enemy. Mr. Mega is no bomb
-- flag and Glitter Bombs' pickups come only from a real bomb, so neither
-- follows. A player is never hurt by a blast (cancelled at IMPORTANT priority).
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
    damageMultiplier = 1, -- a blast, of the holder's damage when the tear was fired
    statMultiplier = 0.33, -- the holder's damage multiplier (StatsAPI)
    tears = -0.2,         -- shots a second
    range = 40 * 40,      -- +40 tiles, in TearRange units
    drops = 3,            -- times a tear lays mines before it is empty
    luckStep = 5,         -- once more for every this much luck, with no upper limit
    placeEvery = 6,       -- a tear lays every this many updates (0.2 s), the first after half of it
    reloadShots = 5,      -- an emptied tear waits this many fire intervals, then holds them all again
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
    crossArms = 2,        -- Bomber Boy: blasts along each arm of the cross, a blast radius apart
    crossRadius = 0.75,   -- and their radius, of the mine's
    scatterCount = 4,     -- Scatter Bombs: small blasts the mine breaks into
    scatterDelay = 8,     -- updates after the mine
    scatterDistance = { 40, 64 }, -- this far from it
    scatterDamage = 0.5,  -- of the mine's damage
    scatterRadius = 0.65, -- of its radius
    beamLength = 40,      -- Brimstone Bombs: each of the four beams reaches as far as the blast
    beamTime = 19,        -- updates a beam lasts
    beamDamage = 0.1,     -- each beam's hit, of the mine's damage (a beam hits about 14 times)
    ghostDamage = 0.5,    -- Ghost Bombs: the ghost's burst, once on each enemy, of the mine's damage
    crawlSpeed = 0.9,     -- Bobby-Bomb: units an update a lying mine creeps
    crawlReach = 200,     -- toward the nearest enemy this close
    gridClear = 30,       -- the engine's bomb damage is dealt only where no grid entity is this close
}

local BLAST_COLOR = Color(0.75, 1, 0.6, 1, 0, 0.06, 0) -- Ipecac's green
local TF = TearFlags or {}
local CROSS_FLAG, SCATTER_FLAG, GHOST_FLAG, HOMING_FLAG = TF.TEAR_CROSS_BOMB, TF.TEAR_SCATTER_BOMB, TF.TEAR_GHOST_BOMB,
    TF.TEAR_HOMING
local BRIM_FLAG = TF.TEAR_BRIMSTONE_BOMB
-- Ghost Bombs: the Purgatory soul (1000.189.1), the same red-tailed ghost 인
-- raises as its 창귀; the engine flies it at an enemy and bursts it there.
local GHOST_SOUL = EffectVariant and EffectVariant.PURGATORY or 189
local GHOST_SUBTYPE = 1
local THICK_LASER = LaserVariant and LaserVariant.THICK_RED or 1
local BLAST_SOUND = SoundEffect.SOUND_EXPLOSION_WEAK or SoundEffect.SOUND_BOOM
local CELL = 40 -- a floor tile, the size of the filing grid
local WEAPON_CACHE = CacheFlag and CacheFlag.CACHE_WEAPON or nil
local TEARS_WEAPON = WeaponType and WeaponType.WEAPON_TEARS or nil
-- Every primary weapon that replaces the tears. The weapons that shoot tears
-- (Monstro's Lung, Ludovico, C Section's fetuses) stay, since their tears lay
-- mines like any other (user decision 2026-11-27), and so do the active items'
-- own weapons (Notched Axe, Urn of Souls).
local OTHER_WEAPONS = {}
for _, name in ipairs({ "WEAPON_BRIMSTONE", "WEAPON_LASER", "WEAPON_KNIFE", "WEAPON_BOMBS", "WEAPON_ROCKETS",
    "WEAPON_TECH_X", "WEAPON_BONE", "WEAPON_SPIRIT_SWORD", "WEAPON_UMBILICAL_WHIP" }) do
    local value = WeaponType and WeaponType[name]
    if type(value) == "number" then OTHER_WEAPONS[#OTHER_WEAPONS + 1] = value end
end
-- The weapons that shoot tears of their own: with one of them the plain tears
-- stay off, as they are without the item (Ludovico fires its one tear only).
local TEAR_WEAPONS = {}
for _, name in ipairs({ "WEAPON_MONSTROS_LUNGS", "WEAPON_LUDOVICO_TECHNIQUE", "WEAPON_FETUS" }) do
    local value = WeaponType and WeaponType[name]
    if type(value) == "number" then TEAR_WEAPONS[#TEAR_WEAPONS + 1] = value end
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
local FRAMES = { Fall = 1, Land = 8, Idle = 30, Walk = 8 }
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
-- Every tear of a holder's that holds mines or waits for them: { ref, owner,
-- damage, load, perDrop, placeIn, reloadIn, side, rng, x, y, vx, vy, ux, uy, lift },
-- (x, y), the velocity and the last direction it moved in as last seen.
local carriers = {}
-- Scatter Bombs' small blasts waiting to go off: { x, y, damage, owner, at }.
local scattered = {}
-- A tear's data key, set once the tear has been looked at (true) so the
-- scan of the room's tears passes it by afterwards.
local SEEN_KEY = "__ConchBlessingLandmine"
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
    evidence = { fired = 0, laid = 0, flung = 0, placed = 0, reloads = 0, spilled = 0, piled = 0, lost = 0,
        carried = 0, landed = 0, bombDamage = 0, flagEffects = 0, crossed = 0, scattered = 0, ghosts = 0, crawled = 0,
        beams = 0,
        flags = nil,
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

-- The mines laid at once by a holder of `copies`: one a copy.
local function perDrop(copies)
    return math.max(1, math.floor(tonumber(copies) or 1))
end

-- The mines a tear holds at `luck` for a holder of `copies`: 3 drops, one more
-- for every 5 luck, of `perDrop` mines each, no upper limit.
local function payload(luck, copies)
    luck = math.max(0, tonumber(luck) or 0)
    return (M.data.drops + math.floor(luck / M.data.luckStep)) * perDrop(copies)
end

-- Whether bomb flags `flags` (a BitSet128, or a number on old builds) hold `flag`.
local function hasFlag(flags, flag)
    if flags == nil or flag == nil then return false end
    local ok, result = pcall(function() return (flags & flag) == flag end)
    return ok and result == true
end

-- Updates an emptied tear waits before it holds its mines again: a number of
-- fire intervals of a holder whose MaxFireDelay is `maxFireDelay`.
local function reloadDelay(maxFireDelay)
    return math.max(1, M.data.reloadShots * ((tonumber(maxFireDelay) or 10) + 1))
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
-- An animation the loaded sheet lacks (the game keeps an anm2 until it is
-- fully restarted, so a newly added Walk is missing after a mere reload) is
-- left out, and a walking mine is drawn as a lying one instead of vanishing.
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
            local first = set[name][1]
            if name ~= "Fall" and type(first.GetAnimation) == "function" and first:GetAnimation() ~= name then
                set[name] = nil
                ConchBlessing.printError("Landmine: " .. SHEET .. " has no " .. name
                    .. " animation; restart the game after anm2 changes")
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
    mines, cells, fresh, fused, pictures, carriers, scattered = {}, {}, {}, {}, {}, {}, {}
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

-- A mine flung from the tear to `side` (-1 or 1) of the way it last moved and
-- a little ahead, onto free floor; false when no spot tried is free (the tear
-- tries again on the next update). `ring` 0 lands 0.15 to 1 tile out, each
-- further ring a tile further, so a drop of many mines spreads wide. A spot
-- ahead that is no floor (a wall, a rock) is turned to the same spot behind,
-- so a tear pressed against a wall (Ludovico held there) still finds floor; a
-- spot ahead that only holds a mine is not, so nothing lands at the shooter's
-- feet.
local function fling(carrier, side, ring)
    local room, d = Game():GetRoom(), M.data
    local ux, uy = carrier.ux, carrier.uy
    local rng = carrier.rng
    ring = ring or 0
    for _ = 1, d.tries do
        local lateral = side * (ring + 0.15 + 0.85 * rng:RandomFloat()) * d.scatter
        local ahead = d.ahead[1] + (d.ahead[2] - d.ahead[1]) * rng:RandomFloat()
        local to = Vector(carrier.x + ux * ahead - uy * lateral, carrier.y + uy * ahead + ux * lateral)
        if not isFloor(room, to) then
            to = Vector(carrier.x - ux * ahead - uy * lateral, carrier.y - uy * ahead + ux * lateral)
        end
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

-- Whether a grid entity that a bomb could hurt lies within `reach` of `at`.
local function gridNear(room, at, reach)
    local width = room:GetGridWidth()
    local index = room:GetGridIndex(at)
    if index < 0 then return true end
    for _, offset in ipairs({ 0, -1, 1, -width, width, -width - 1, -width + 1, width - 1, width + 1 }) do
        local grid = room:GetGridEntity(index + offset)
        if grid and grid.CollisionClass ~= GridCollisionClass.COLLISION_NONE
            and grid.CollisionClass ~= GridCollisionClass.COLLISION_PIT
            and grid.Position:Distance(at) < reach then
            return true
        end
    end
    return false
end

-- Every vulnerable, unfriendly enemy within `radius` (plus its size) of
-- `position` takes `damage` from `owner` (nil: a source-less blast). With the
-- owner's bomb `flags` it is the engine's own bomb damage at that enemy's spot
-- with radius 1, which carries the flags' statuses and leaves the grid alone
-- while no grid entity is close; otherwise plain explosion damage.
local function strike(position, radius, damage, owner, flags)
    blasting = true
    local game, room = Game(), Game():GetRoom()
    local bombDamage = flags ~= nil and type(game.BombDamage) == "function"
    local source = EntityRef(owner)
    for _, entity in ipairs(Isaac.FindInRadius(position, radius + 80, EntityPartition.ENEMY)) do
        if entity:IsVulnerableEnemy() and not entity:HasEntityFlags(EntityFlag.FLAG_FRIENDLY)
            and within(entity.Position:Distance(position), radius, entity.Size) then
            if bombDamage and not gridNear(room, entity.Position, M.data.gridClear) then
                game:BombDamage(entity.Position, damage, 1, false, owner, flags, DamageFlag.DAMAGE_EXPLOSION, false)
                evidence.bombDamage = evidence.bombDamage + 1
            else
                entity:TakeDamage(damage, DamageFlag.DAMAGE_EXPLOSION, source, 0)
            end
            evidence.struck = evidence.struck + 1
        end
    end
    blasting = false
end

local function picture(at, scale)
    if not newPicture(at.X, at.Y, Game():GetFrameCount()) then return end
    local blast = Isaac.Spawn(EntityType.ENTITY_EFFECT, EffectVariant.BOMB_EXPLOSION, 0, at, Vector.Zero, nil)
    if blast then
        blast.SpriteScale = Vector(scale, scale)
        blast.Color = BLAST_COLOR
    end
    evidence.pictures = evidence.pictures + 1
end

local CROSS_DIRS = { Vector(1, 0), Vector(-1, 0), Vector(0, 1), Vector(0, -1) }

-- Every landed mine within `radius` of (x, y) not yet on its way goes off a
-- moment later: any blast does this, the cross's arms and Scatter Bombs'
-- small blasts included (user request 2026-11-27).
local function chainAround(x, y, radius, except)
    for k = 1, gather(x, y, radius) do
        local other = nearby[k]
        if other ~= except and other.landed and not other.dead and not other.fuse and not other.going then
            local dx, dy = other.x - x, other.y - y
            if dx * dx + dy * dy <= radius * radius then
                other.fuse = M.data.chainDelay
                fused[#fused + 1] = other
                evidence.chained = evidence.chained + 1
            end
        end
    end
end

-- What the owner's bomb flags add to a mine's blast at `position`: Bomber
-- Boy's cross, the engine's own flag effects, a Ghost Bombs soul, and Scatter
-- Bombs' small blasts queued for a moment later. Runs inside the blast's
-- triggered source, so what it makes carries the landmine proc.
local function bombEffects(position, radius, damage, owner, flags, rng)
    local game, room, d = Game(), Game():GetRoom(), M.data
    if hasFlag(flags, CROSS_FLAG) then
        for _, dir in ipairs(CROSS_DIRS) do
            for step = 1, d.crossArms do
                local at = position + dir * (radius * step)
                if not isFloor(room, at) then break end
                picture(at, d.blastScale * 0.85)
                strike(at, radius * d.crossRadius, damage, owner, flags)
                chainAround(at.X, at.Y, radius * d.crossRadius)
                evidence.crossed = evidence.crossed + 1
            end
        end
    end
    local brimstone = hasFlag(flags, BRIM_FLAG)
    if type(game.BombTearflagEffects) == "function" then
        -- The engine's own Brimstone Bombs beams cross the whole room; ours below
        -- take their place, so the flag is left out of this call.
        local rest = flags
        if brimstone then
            local ok, without = pcall(function() return flags ~ BRIM_FLAG end)
            if not ok then ok, without = pcall(function() return flags & ~BRIM_FLAG end) end
            rest = ok and without or flags
        end
        game:BombTearflagEffects(position, radius, rest, owner, 1)
        evidence.flagEffects = evidence.flagEffects + 1
    end
    if brimstone and EntityLaser and type(EntityLaser.ShootAngle) == "function" then
        -- Four Brimstone beams from the mine, each ending where the blast ends.
        for k = 0, 3 do
            local laser = EntityLaser.ShootAngle(THICK_LASER, position, k * 90, d.beamTime, Vector.Zero, owner)
            if laser then
                laser.DisableFollowParent = true
                laser.Position = position
                if type(laser.SetMaxDistance) == "function" then laser:SetMaxDistance(d.beamLength)
                else laser.MaxDistance = d.beamLength end
                laser.CollisionDamage = damage * d.beamDamage
                evidence.beams = evidence.beams + 1
            end
        end
    end
    if hasFlag(flags, GHOST_FLAG) then
        local seed = rng:Next()
        if seed == 0 then seed = 1 end
        local soul = game:Spawn(EntityType.ENTITY_EFFECT, GHOST_SOUL, position, Vector.Zero, owner, GHOST_SUBTYPE, seed)
        local tiger = ConchBlessing.tiger
        if soul and tiger and type(tiger.adoptSoul) == "function" then
            tiger.adoptSoul(soul, owner, { damage = damage * d.ghostDamage, fear = false, procKey = PROC_KEY })
        end
        evidence.ghosts = evidence.ghosts + 1
    end
    if hasFlag(flags, SCATTER_FLAG) then
        local now = game:GetFrameCount()
        for k = 1, d.scatterCount do
            local angle = (k - 1 + rng:RandomFloat() * 0.6 - 0.3) * 2 * math.pi / d.scatterCount
            local distance = d.scatterDistance[1] + (d.scatterDistance[2] - d.scatterDistance[1]) * rng:RandomFloat()
            local at = Vector(position.X + math.cos(angle) * distance, position.Y + math.sin(angle) * distance)
            if isFloor(room, at) then
                scattered[#scattered + 1] = { x = at.X, y = at.Y, damage = damage * d.scatterDamage,
                    owner = EntityPtr(owner), at = now + d.scatterDelay }
            end
        end
    end
end

-- The player's bomb flags, or nil when they hold none (a blast then stays the
-- plain one it always was).
local function bombFlags(player)
    if not player or type(player.GetBombFlags) ~= "function" then return nil end
    local ok, flags = pcall(player.GetBombFlags, player)
    if not ok or flags == nil then return nil end
    if type(flags) == "number" then return flags ~= 0 and flags or nil end
    local none = TF.TEAR_NORMAL
    local same, empty = pcall(function() return flags == none end)
    if none ~= nil and same and empty then return nil end
    return flags
end

-- The live player a mine (or a small blast) belongs to, or nil.
local function livingOwner(ref)
    local owner = ref and ref.Ref
    return owner and owner:Exists() and owner:ToPlayer() or nil
end

-- Scatter Bombs' small blasts whose moment came: each a picture and its
-- damage with the owner's statuses, nothing more.
local function burnScattered()
    if #scattered == 0 then return end
    local now, still = Game():GetFrameCount(), {}
    local d = M.data
    for _, small in ipairs(scattered) do
        if now >= small.at then
            local at = Vector(small.x, small.y)
            picture(at, d.blastScale * d.scatterRadius)
            local owner = livingOwner(small.owner)
            local radius = d.blastRadius * d.scatterRadius
            if owner then
                local flags = bombFlags(owner)
                DamageProvenance.withTriggeredSource(owner, PROC_KEY, nil, PROC_KEY, function()
                    strike(at, radius, small.damage, owner, flags)
                end)
            else
                strike(at, radius, small.damage, nil, nil)
            end
            chainAround(small.x, small.y, radius)
            evidence.scattered = evidence.scattered + 1
        else
            still[#still + 1] = small
        end
    end
    scattered = still
end

local function explode(record)
    if record.dead then return end
    local position = record.spot
    local frame = Game():GetFrameCount()
    picture(position, M.data.blastScale)
    if BLAST_SOUND and frame ~= soundFrame then
        soundFrame = frame
        SFXManager():Play(BLAST_SOUND, Sound.volume(0.8), 0, false, 1.1)
    end
    local damage, radius = mineDamage(record.damage), M.data.blastRadius
    -- The owner is the source, marked with this proc so the blast's hits and
    -- what its bomb flags make (Sad Bombs' tears, beams, souls) never lay or
    -- set off mines again through it; a mine whose owner left the run strikes
    -- with no source and no flags.
    local owner = livingOwner(record.owner)
    if owner then
        local flags = bombFlags(owner)
        evidence.flags = flags
        DamageProvenance.withTriggeredSource(owner, PROC_KEY, nil, PROC_KEY, function()
            strike(position, radius, damage, owner, flags)
            if flags then
                local rng = RNG()
                rng:SetSeed(math.max(1, (record.key % 100000) * 31 + frame), 35)
                bombEffects(position, radius, damage, owner, flags, rng)
            end
        end)
    else
        strike(position, radius, damage, nil, nil)
    end
    chainAround(record.x, record.y, radius, record)
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

-- Bobby-Bomb: every lying, armed mine whose owner's bombs home stands up on
-- its legs and creeps toward the nearest active enemy within reach, over
-- floor only; once it has stood up it keeps its legs.
local function crawl()
    local homing, enemies, room, d = {}, nil, Game():GetRoom(), M.data
    for k = 1, #mines do
        local r = mines[k]
        if not r.dead and r.armed and r.idle and not r.fuse and not r.going then
            local owner = r.owner and r.owner.Ref
            local hash = owner and GetPtrHash(owner)
            local moves = false
            if hash then
                moves = homing[hash]
                if moves == nil then
                    local player = livingOwner(r.owner)
                    moves = player ~= nil and hasFlag(bombFlags(player), HOMING_FLAG)
                    homing[hash] = moves
                end
            end
            r.walking = false
            if moves then
                if not enemies then
                    enemies = {}
                    for _, entity in ipairs(Isaac.FindInRadius(room:GetCenterPos(), 4000, EntityPartition.ENEMY)) do
                        if entity:IsActiveEnemy(false) and not entity:HasEntityFlags(EntityFlag.FLAG_FRIENDLY) then
                            enemies[#enemies + 1] = entity.Position
                        end
                    end
                end
                local best, bestDistance = nil, d.crawlReach * d.crawlReach
                for _, at in ipairs(enemies) do
                    local dx, dy = at.X - r.x, at.Y - r.y
                    local distance = dx * dx + dy * dy
                    if distance < bestDistance then best, bestDistance = at, distance end
                end
                if best and bestDistance > 1 then
                    local length = math.sqrt(bestDistance)
                    local to = Vector(r.x + (best.X - r.x) / length * d.crawlSpeed,
                        r.y + (best.Y - r.y) / length * d.crawlSpeed)
                    if isFloor(room, to) then
                        unfile(r)
                        r.x, r.y, r.spot = to.X, to.Y, to
                        r.key = keyOf(tileOf(to.X), tileOf(to.Y))
                        file(r)
                        r.drawStamp, r.walking = nil, true
                        if not r.legs then r.legs, r.walkAt = true, Game():GetFrameCount() end
                        evidence.crawled = evidence.crawled + 1
                    end
                end
            end
        end
    end
end

-- Every tear holding mines: a live one lays its mines at once every 0.2 s
-- while it holds them (one, a pair, three: one a copy, to alternating sides),
-- and from the first mine it lays out of a full stock waits and holds them
-- all again (while its holder still holds the item); one that stopped spills
-- the rest.
local function carry()
    local still = {}
    local d = M.data
    for _, carrier in ipairs(carriers) do
        local tear = carrier.ref.Ref
        if tear and tear:Exists() then
            local position, velocity = tear.Position, tear.Velocity
            carrier.x, carrier.y, carrier.vx, carrier.vy = position.X, position.Y, velocity.X, velocity.Y
            local speed = math.sqrt(velocity.X * velocity.X + velocity.Y * velocity.Y)
            if speed > 0.01 then carrier.ux, carrier.uy = velocity.X / speed, velocity.Y / speed end
            carrier.lift = math.min(0, tonumber(tear.Height) or carrier.lift)
            local player = carrierPlayer(carrier)
            local holder = player and player:GetCollectibleNum(ID) > 0 and isActingPlayer(player)
            -- The refill: it runs from the first mine laid out of a full stock and
            -- then fills the whole stock at once (user decision 2026-11-27).
            if carrier.reloadIn and holder then
                carrier.reloadIn = carrier.reloadIn - 1
                if carrier.reloadIn <= 0 then
                    local copies = player:GetCollectibleNum(ID)
                    carrier.full, carrier.perDrop = payload(player.Luck, copies), perDrop(copies)
                    carrier.load, carrier.damage, carrier.reloadIn = carrier.full, player.Damage, nil
                    evidence.reloads = evidence.reloads + 1
                end
            end
            -- A drop starts every 0.2 s with `perDrop` mines to lay, each to the
            -- other side from the last; one that finds no free ground waits for
            -- the next update, and so do the rest of its drop.
            carrier.placeIn = carrier.placeIn - 1
            if (carrier.pending or 0) == 0 and carrier.placeIn <= 0 and carrier.load >= carrier.perDrop then
                carrier.pending, carrier.placeIn = carrier.perDrop, d.placeEvery
                evidence.placed = evidence.placed + 1
            end
            while (carrier.pending or 0) > 0 do
                local ring = (carrier.perDrop - carrier.pending) // 2 -- the 1st and 2nd mine of a drop on ring 0
                if fling(carrier, carrier.side, ring) then
                    carrier.pending, carrier.load, carrier.side = carrier.pending - 1, carrier.load - 1, -carrier.side
                else
                    evidence.carried = evidence.carried + 1
                    break
                end
            end
            if holder and not carrier.reloadIn and carrier.load < carrier.full then
                carrier.reloadIn = reloadDelay(player.MaxFireDelay)
            end
            if carrier.load > 0 or holder then still[#still + 1] = carrier end
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
-- (REPENTOGON); the next evaluation without the item rebuilds the weapons. The
-- plain tears come on only when no weapon that shoots tears of its own is left
-- (enabling them beside Ludovico made it fire plain tears too, user report
-- 2026-11-27).
local function lockTears(player)
    if type(player.EnableWeaponType) ~= "function" or type(TEARS_WEAPON) ~= "number" then return false end
    for _, weapon in ipairs(OTHER_WEAPONS) do player:EnableWeaponType(weapon, false) end
    if type(player.HasWeaponType) == "function" then
        for _, weapon in ipairs(TEAR_WEAPONS) do
            if player:HasWeaponType(weapon) then return true end
        end
    end
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

-- The player a tear belongs to: its spawner (or parent), followed through
-- tears made by tears (another mod's satellites, splits); a tear a familiar,
-- an effect or an enemy made is not a player's own.
local function tearOwner(tear)
    local entity = tear
    for _ = 1, 4 do
        local spawner = entity.SpawnerEntity or entity.Parent
        if not spawner then return nil end
        local player = spawner:ToPlayer()
        if player then return player end
        if spawner.Type ~= EntityType.ENTITY_TEAR then return nil end
        entity = spawner
    end
    return nil
end

-- Whether a tear lays mines: seen, harmful, not made by a mine's blast (so
-- mines never feed themselves), and a living holder's own. Returns the holder.
local function minesFor(tear)
    if tear.Visible == false or (tonumber(tear.CollisionDamage) or 1) <= 0 then return nil end
    local lineage = DamageProvenance.resolve(tear)
    if lineage and lineage.procChain and lineage.procChain[PROC_KEY] then return nil end
    local player = tearOwner(tear)
    if not player or player:GetCollectibleNum(ID) <= 0 or not isActingPlayer(player) then return nil end
    return player
end

-- Takes up a tear: it holds its mines from now on.
local function take(tear, player)
    local rng = RNG()
    rng:SetSeed(math.max(1, tear.InitSeed or 1), 35)
    local position, velocity = tear.Position, tear.Velocity
    local speed = math.sqrt(velocity.X * velocity.X + velocity.Y * velocity.Y)
    local ux, uy
    if speed > 0.01 then
        ux, uy = velocity.X / speed, velocity.Y / speed
    else
        local angle = rng:RandomFloat() * 2 * math.pi
        ux, uy = math.cos(angle), math.sin(angle)
    end
    local copies = player:GetCollectibleNum(ID)
    local full = payload(player.Luck, copies)
    carriers[#carriers + 1] = { ref = EntityPtr(tear), owner = EntityPtr(player), damage = player.Damage,
        load = full, full = full, perDrop = perDrop(copies), placeIn = math.floor(M.data.placeEvery / 2),
        side = rng:RandomFloat() < 0.5 and -1 or 1, rng = rng, x = position.X, y = position.Y,
        vx = velocity.X, vy = velocity.Y, ux = ux, uy = uy, lift = math.min(0, tonumber(tear.Height) or 0) }
    evidence.fired = evidence.fired + 1
end

-- Looks once at every tear in the room it has not seen yet.
local function scan()
    for _, entity in ipairs(Isaac.FindByType(EntityType.ENTITY_TEAR)) do
        local data = entity:GetData()
        if not data[SEEN_KEY] then
            data[SEEN_KEY] = true
            local tear = entity:ToTear()
            local player = tear and minesFor(tear)
            if player then take(tear, player) end
        end
    end
end

-- Whether SaveManager has loaded the run: re-evaluating a player's items
-- before that makes every other item's cache handler read a save that is not
-- there yet (a mid-run reload loads it only after the first updates).
local function saveLoaded()
    local manager = ConchBlessing.SaveManager
    return not manager or type(manager.IsLoaded) ~= "function" or manager.IsLoaded()
end

function M.onUpdate()
    local anyHolder = false
    if ID > 0 then
        local game = Game()
        local ready = saveLoaded()
        for i = 0, game:GetNumPlayers() - 1 do
            local player = Isaac.GetPlayer(i)
            if player then
                if ready then syncHolder(player) end
                if not anyHolder and player:GetCollectibleNum(ID) > 0 and isActingPlayer(player) then
                    anyHolder = true
                end
            end
        end
        if ready then sweep = false end
    end
    if anyHolder and M.available then scan() end
    if #carriers > 0 then carry() end
    burnScattered()
    if #mines == 0 then return end
    compact()
    settleFresh()
    burnFuses()
    if #mines > 0 then crawl() end
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
    local fall, land, idle, walk = set.Fall[1], set.Land, set.Idle, set.Walk
    local landCount, idleCount, walkCount = FRAMES.Land, FRAMES.Idle, FRAMES.Walk
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
                if r.legs and walk then
                    walk[r.walking and (now - r.walkAt) % walkCount + 1 or 1]:Render(at)
                elseif r.idle then
                    idle[(now - r.idleAt) % idleCount + 1]:Render(at)
                else
                    land[math.max(0, math.min(landCount - 1, now - r.landedAt)) + 1]:Render(at)
                end
            end
        end
    end
    evidence.drawn, evidence.drawnMines = evidence.drawn + 1, drew
end

-- A blast never hurts a player, whatever the engine's bomb damage reaches;
-- cancelled before every other handler counts it as a hit.
function M.onPlayerDamage(_, entity)
    if blasting and entity and entity.Type == EntityType.ENTITY_PLAYER then return false end
end
if ModCallbacks and ModCallbacks.MC_ENTITY_TAKE_DMG and ConchBlessing.AddPriorityCallback then
    local important = (CallbackPriority and CallbackPriority.IMPORTANT) or -200
    ConchBlessing:AddPriorityCallback(ModCallbacks.MC_ENTITY_TAKE_DMG, important, M.onPlayerDamage, EntityType.ENTITY_PLAYER)
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
    perDrop = perDrop,
    hasFlag = hasFlag,
    gridNear = gridNear,
    scattered = function() return scattered end,
    reloadDelay = reloadDelay,
    tearOwner = tearOwner,
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
