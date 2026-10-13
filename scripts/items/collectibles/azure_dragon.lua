-- 청룡 (Azure Dragon): a long azure dragon familiar per copy. Console only: it
-- is hidden and in no pool, like Inf D6 (진, the Dragon item, is the weather).
--
-- The dragon weaves around its player like a living creature and rushes at
-- any enemy in the room, swimming at it in a gently weaving line (wave
-- pursuit). It hurts every enemy its body touches each tick, and lightning
-- strikes every enemy its snout runs into, at most once every five seconds each
-- (bosses take five times more). Several dragons spread out, each going for
-- an enemy no other dragon is already after when there is one. Small sparks of current crackle along its
-- body now and then; they are drawn only and hurt nothing.
-- docs/guidance_methods.md names every steering method used here.
--
-- Every part follows one orientation rule: drawn facing right with its back
-- up, a part heading left is mirrored top-to-bottom so its back stays up.
-- Each part decides from its own direction, with a small band around vertical
-- so it never flickers, so a turn travels naturally from head to tail; nothing
-- is squashed. Like a rig, the head leads and the
-- body follows: the head always swims forward and its turning speed itself
-- eases in and out, so its direction never jumps; every other part sits on
-- the exact trail the head left behind, so the body never bunches or kinks.
-- The dragon keeps its own head position and sets the entity to it each
-- update rather than relying on the engine to integrate a velocity.
-- Motion and drawing are cosmetic; damage always goes through
-- Entity:TakeDamage with the familiar as its source.
ConchBlessing.azureDragon = {}

local DRAGON_ID = Isaac.GetItemIdByName("Azure Dragon")
local THUNDER_SOUND = "Conch Upgrade Thunder Strike"

ConchBlessing.azureDragon.data = {
    -- Head, a long body and the tail; legs hang under the front and hind parts.
    parts = { "Head", "Body", "Body", "Body", "Body", "Body", "Body", "Body",
              "Body", "Body", "Body", "Body", "Body", "Tail" },
    legParts = { [3] = true, [9] = true },
    flipThreshold = 0.08,                -- heading cosine (about 5 degrees past vertical) at which a part turns round
    spacing = { 10, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 10 },  -- trail distance between part pivots
    taper = 0.35,                        -- the tail end is drawn this much smaller than the head
    flyHeight = 7,                       -- the body floats above its shadow...
    liftWave = 3, liftRate = 0.12, liftStep = 0.55,  -- ...rising and dipping along its length
    orbitRadius = 74,
    radiusSwing = 22, radiusSwing2 = 9,  -- the orbit breathes in and out
    orbitSquash = 0.78,                  -- Isaac's floor is seen at an angle
    angularSpeed = 0.045,                -- radians per update before the speed swings
    speedSwing = 0.45, speedSwing2 = 0.25,
    -- The head always swims forward. Its turn velocity eases toward what the
    -- goal asks for (turnGain), never faster than turnAccel per update and
    -- never beyond the turn-rate cap, so its path is one smooth curve.
    turnGain = 0.15, turnAccel = 0.02,
    idleTurnRate = 0.08, hurryTurnRate = 0.2,
    turnSlowdown = 0.7,                  -- share of speed kept while the goal is behind
    minTurnRadius = 30,                  -- the head never curls tighter than this, so the body bends smoothly
    minSpeed = 1.2, maxSpeed = 15,
    hurryDistance = 120,                 -- this far outside the orbit, the turn rate rises to hurryTurnRate
    radialGain = 0.04,                   -- tilt toward the orbit per unit of distance off it
    weave = 0.2, weaveRate = 0.06,       -- gentle side-to-side swimming
    catchUp = 0.15,                      -- extra speed per unit of distance outside the orbit
    speedEase = 0.1,
    -- Any enemy in the room draws the dragon off its orbit: wave pursuit,
    -- heading for the enemy with a slow sine weave on top of the bearing.
    -- Once the head runs into its prey it flies straight on through (a fly-by)
    -- and then goes for the enemy it has passed least recently, so its hits
    -- spread over every enemy instead of coiling round one.
    -- The hunt is fast and decisive: a quick dash, and a sharp (but still
    -- eased) turn the moment a new target is chosen, so the switch is plain to see.
    chaseSpeed = 8, chaseSpeedEase = 0.25,
    chaseTurnRate = 0.2, chaseTurnAccel = 0.045,
    chaseWeave = 0.15, chaseWeaveRate = 0.07,
    passReach = 6,                       -- head within headReach + this + the enemy's size runs into it
    passTicks = 12,                      -- updates it keeps straight on after running through
    trailStep = 0.5,                     -- smallest head move recorded on the trail
    teleportStep = 96,                   -- the player moving this far in one update has teleported
    snapDistance = 1600,                 -- failsafe: never this far from the player, even while hunting
    legFrameTicks = 5, tailFrameTicks = 8,
    headReach = 14,                      -- the snout reaches this far ahead of the neck
    contactDamagePercent = 0.05,         -- of the player's damage, per tick, per enemy
    contactRadius = 8,                   -- per part, plus the enemy's own size
    lightningDamageMultiplier = 5,
    lightningBossMultiplier = 5,
    strikeCooldown = 150,                -- one lightning bolt per enemy every five seconds, per dragon
    bffsDamageMultiplier = 2,
    bffsScale = 1.25,
    strikeFrames = { 1, 2, 2, 2, 2, 2, 3 },  -- ticks per lightning frame: leader, strike, flash, second stroke, flicker, thin, fade
    -- Sparks of current crackling along the body (drawn only).
    sparkGap = { 6, 14 },                -- updates between sparks, rolled from the dragon's own seed
    sparkFrames = 3,                     -- the Spark animation's frames...
    sparkFrameTicks = 2,                 -- ...each this many updates on screen
    sparkSpread = 5,                     -- off the spine to either side, before scaling
}

local PART_ANIMATIONS = ConchBlessing.azureDragon.data.parts
ConchBlessing.azureDragon._strikes = {}
local enemyCache = { frame = -1, list = {} }
-- Every dragon's state and the frame it last updated, so several dragons can
-- spread over different enemies. Weak keys: a removed dragon drops out.
local liveStates = setmetatable({}, { __mode = "k" })
local reportedRenderFailure = false
local strikeCount = 0
local thunderSound

local function debugLog(format, ...)
    if not (ConchBlessing.Config and ConchBlessing.Config.debugMode) then return end
    ConchBlessing.printDebug("[Azure Dragon] " .. string.format(format, ...))
end

local function getVariant()
    local item = ConchBlessing.ItemData.AZURE_DRAGON
    return item and item.entity and item.entity.variant
end

local function ownedCount(player)
    return player and player:GetCollectibleNum(DRAGON_ID) or 0
end

-- One dragon per copy: owned copies plus temporary effects (Box of Friends,
-- Monster Manual), like any other familiar item.
local function familiarCount(player)
    local effects = player:GetEffects()
    local temporary = effects and effects:GetCollectibleEffectNum(DRAGON_ID) or 0
    return ownedCount(player) + temporary
end

local function hasBffs(player)
    return player and player:HasCollectible(CollectibleType.COLLECTIBLE_BFFS) or false
end

-- ------------------------------------------------------------------ pure rules
-- Kept free of engine state so tests can exercise them directly.
local function contactDamage(playerDamage, bffs)
    local d = ConchBlessing.azureDragon.data
    return playerDamage * d.contactDamagePercent * (bffs and d.bffsDamageMultiplier or 1)
end

local function lightningDamage(playerDamage, isBoss, bffs)
    local d = ConchBlessing.azureDragon.data
    return playerDamage * d.lightningDamageMultiplier * (isBoss and d.lightningBossMultiplier or 1)
        * (bffs and d.bffsDamageMultiplier or 1)
end

-- Angular speed and orbit radius at time t: two slow sine swings with
-- per-dragon phases, so the path never settles into a mechanical circle.
local function orbitShape(state, t)
    local d = ConchBlessing.azureDragon.data
    local speed = d.angularSpeed * (1 + d.speedSwing * math.sin(t * 0.031 + state.p1)
        + d.speedSwing2 * math.sin(t * 0.077 + state.p2))
    local radius = d.orbitRadius + d.radiusSwing * math.sin(t * 0.023 + state.p3)
        + d.radiusSwing2 * math.sin(t * 0.061 + state.p4)
    return speed, radius
end

local function wrapAngle(a)
    return (a + math.pi) % (2 * math.pi) - math.pi
end

local function trailLength()
    local total = 0
    for _, gap in ipairs(ConchBlessing.azureDragon.data.spacing) do total = total + gap end
    return total
end

-- The head's trail, newest point first. A move shorter than trailStep slides
-- the newest point instead of adding one; points past the body's length drop off.
local function pushTrail(trail, head)
    local d = ConchBlessing.azureDragon.data
    local first = trail[1]
    if first and first:Distance(head) < d.trailStep and trail[2] then
        trail[1] = head
    else
        table.insert(trail, 1, head)
    end
    local need, travelled = trailLength() + 4, 0
    for i = 2, #trail do
        travelled = travelled + trail[i]:Distance(trail[i - 1])
        if travelled > need then
            for j = #trail, i + 1, -1 do trail[j] = nil end
            break
        end
    end
end

-- The point `distance` along the trail behind the head. Past the recorded end
-- the trail continues straight back.
local function sampleTrail(trail, distance, heading)
    local travelled = 0
    for i = 2, #trail do
        local a, b = trail[i - 1], trail[i]
        local length = b:Distance(a)
        if length > 0 and travelled + length >= distance then
            return a + (b - a) * ((distance - travelled) / length)
        end
        travelled = travelled + length
    end
    local last, before = trail[#trail], trail[#trail - 1]
    local back = before and last - before
    if not back or back:Length() < 0.001 then back = Vector(-math.cos(heading), -math.sin(heading)) end
    return last + back:Resized(distance - travelled)
end

-- Every part's position and angle, laid on the trail; the head points along its heading.
local function layOut(trail, heading)
    local d = ConchBlessing.azureDragon.data
    local positions, angles = {}, {}
    local offset = 0
    for i = 1, #d.parts do
        if i > 1 then offset = offset + (d.spacing[i - 1] or d.spacing[#d.spacing]) end
        positions[i] = sampleTrail(trail, offset, heading)
        if i == 1 then
            angles[i] = heading
        else
            local toward = sampleTrail(trail, math.max(0, offset - 5), heading) - sampleTrail(trail, offset + 5, heading)
            angles[i] = toward:Length() > 0.001 and math.atan(toward.Y, toward.X) or angles[i - 1]
        end
    end
    return positions, angles
end

-- How large a part is drawn: full size at the head, thinning toward the tail.
local function partTaper(index)
    local d = ConchBlessing.azureDragon.data
    return 1 - d.taper * ((index - 1) / (#d.parts - 1)) ^ 1.4
end

-- ------------------------------------------------------------------ state
local function copyVector(v) return Vector(v.X, v.Y) end

local function straightTrail(position, heading)
    local back = Vector(-math.cos(heading), -math.sin(heading))
    return { copyVector(position), position + back * (trailLength() + 4) }
end

-- Whether a part faces left: past vertical by the flipThreshold band, else
-- whatever it faced before, so swimming straight up or down never flickers.
local function facesLeft(angle, current)
    local c = math.cos(angle)
    local threshold = ConchBlessing.azureDragon.data.flipThreshold
    if c < -threshold then return true end
    if c > threshold then return false end
    if current == nil then return c < 0 end
    return current
end

-- The single orientation rule for drawing any part. The engine applies the
-- mirror after the rotation (on screen), so a mirrored part takes the negated
-- angle to point the same way.
local function orient(sprite, angle, mirrored)
    local degrees = math.deg(angle)
    sprite.FlipY = mirrored
    sprite.Rotation = mirrored and -degrees or degrees
end

-- Lay the parts on the current trail, keeping the last pose for render interpolation.
local function settle(state, keepPrevious)
    local positions, angles = layOut(state.trail, state.dir)
    for i = 1, #positions do
        if keepPrevious then
            state.previous[i], state.prevAngles[i] = state.segments[i], state.angles[i]
        else
            state.previous[i], state.prevAngles[i] = positions[i], angles[i]
            state.flips[i] = nil
        end
        state.segments[i], state.angles[i] = positions[i], angles[i]
        state.flips[i] = facesLeft(angles[i], state.flips[i])
    end
end

local function newState(familiar)
    -- Cosmetic phases from the familiar's own seed; no gameplay RNG is consumed.
    local seed = familiar.InitSeed or 1
    local function phase(k) return ((seed // k) % 997) / 997 * 2 * math.pi end
    local player = familiar.Player
    local origin = player and player.Position or familiar.Position
    local offset = familiar.Position - origin
    local theta = offset:Length() > 1 and math.atan(offset.Y, offset.X) or phase(3)
    local dir = theta + math.pi / 2               -- start swimming along the orbit
    local state = {
        t = 0, p1 = phase(1), p2 = phase(7), p3 = phase(13), p4 = phase(29),
        theta = theta, dir = dir, turnVel = 0, speed = ConchBlessing.azureDragon.data.minSpeed,
        head = copyVector(familiar.Position),
        velocity = Vector(0, 0), trail = straightTrail(familiar.Position, dir),
        segments = {}, previous = {}, angles = {}, prevAngles = {}, flips = {}, passed = {},
        struck = {}, renders = 0,
        sparks = {}, sparkWait = ConchBlessing.azureDragon.data.sparkGap[1], sparkSeed = seed % 2147483647 + 1,
    }
    settle(state, false)
    return state
end

local function getState(familiar)
    local data = familiar:GetData()
    if not data.__ConchDragon then data.__ConchDragon = newState(familiar) end
    return data.__ConchDragon
end

local function snapTo(state, position)
    state.head = copyVector(position)
    state.playerAt = copyVector(position)
    state.trail = straightTrail(position, state.dir)
    state.velocity = Vector(0, 0)
    state.turnVel, state.prey, state.passing, state.passed = 0, nil, nil, {}
    settle(state, false)
end

-- ------------------------------------------------------------------ enemies
local function isTarget(entity)
    return entity and entity:Exists() and entity:IsVulnerableEnemy() and entity:IsActiveEnemy(false)
        and not entity:IsDead() and not entity:HasEntityFlags(EntityFlag.FLAG_FRIENDLY)
end

-- One room scan per update, shared by every dragon.
local function roomEnemies()
    local frame = Game():GetFrameCount()
    if enemyCache.frame ~= frame then
        enemyCache.frame, enemyCache.list = frame, {}
        for _, entity in ipairs(Isaac.GetRoomEntities()) do
            local npc = entity:ToNPC()
            if npc and isTarget(npc) then enemyCache.list[#enemyCache.list + 1] = npc end
        end
    end
    return enemyCache.list
end

local function scaleFor(player)
    return hasBffs(player) and ConchBlessing.azureDragon.data.bffsScale or 1
end

-- Body contact: every enemy touched by any part takes contact damage once
-- this tick. Returns the enemies the snout ran into.
local function applyContact(familiar, state, player)
    local d = ConchBlessing.azureDragon.data
    local damage = contactDamage(player.Damage, hasBffs(player))
    local scale = scaleFor(player)
    local reach = d.contactRadius * scale
    -- The snout, which reaches ahead of the neck, then the parts' pivots.
    local points = { state.segments[1] + Vector(math.cos(state.dir), math.sin(state.dir)) * (d.headReach * scale) }
    for i, segment in ipairs(state.segments) do points[i + 1] = segment end
    local snouted = {}
    for _, enemy in ipairs(roomEnemies()) do
        local limit = reach + (enemy.Size or 0)
        for k, point in ipairs(points) do
            if point:DistanceSquared(enemy.Position) <= limit * limit then
                -- Once per enemy per tick, however many parts touch it.
                enemy:TakeDamage(damage, 0, EntityRef(familiar), 0)
                if k == 1 then snouted[#snouted + 1] = enemy end
                break
            end
        end
    end
    return snouted
end

-- ------------------------------------------------------------------ lightning
local function getThunderSound()
    if thunderSound == nil then
        local id = Isaac.GetSoundIdByName and Isaac.GetSoundIdByName(THUNDER_SOUND)
        thunderSound = type(id) == "number" and id > 0 and id or false
        if not thunderSound then ConchBlessing.printError("[Azure Dragon] missing sound: " .. THUNDER_SOUND) end
    end
    return thunderSound or nil
end

local function strikeEnemy(familiar, player, enemy)
    local isBoss = enemy:IsBoss()
    local damage = lightningDamage(player.Damage, isBoss, hasBffs(player))
    enemy:TakeDamage(damage, 0, EntityRef(familiar), 0)
    local strikes = ConchBlessing.azureDragon._strikes
    strikeCount = strikeCount + 1
    -- Four bolt shapes, either way round; cosmetic, so no gameplay RNG.
    strikes[#strikes + 1] = { position = copyVector(enemy.Position), age = 0,
        shape = strikeCount % 4 + 1, flip = strikeCount % 3 == 0 }
    local sound = getThunderSound()
    if sound then SFXManager():Play(sound, require("scripts.lib.sound_volume").volume(0.5), 0, false, 1) end
    Game():ShakeScreen(3)
    debugLog("strike %s.%s boss=%s damage=%.2f", tostring(enemy.Type), tostring(enemy.Variant), tostring(isBoss), damage)
end

-- Lightning on every enemy the snout runs into, once per strikeCooldown each
-- (per dragon: every dragon keeps its own record).
local function updateLightning(familiar, state, player, snouted)
    local d = ConchBlessing.azureDragon.data
    for _, enemy in ipairs(snouted) do
        local hash = GetPtrHash(enemy)
        local last = state.struck[hash]
        if not last or state.t - last >= d.strikeCooldown then
            state.struck[hash] = state.t
            strikeEnemy(familiar, player, enemy)
        end
    end
end

-- ------------------------------------------------------------------ sparks
-- Cosmetic dice from the dragon's own seed (a small LCG), never gameplay RNG.
local function cosmeticRoll(seed)
    seed = (seed * 1103515245 + 12345) % 2147483648
    return seed, seed / 2147483648
end

-- Age the sparks and drop spent ones; every few updates light a new one on a
-- random part, turned any way and a little off the spine.
local function updateSparks(state)
    local d = ConchBlessing.azureDragon.data
    state.sparks = state.sparks or {}
    state.sparkWait = state.sparkWait or d.sparkGap[1]
    state.sparkSeed = state.sparkSeed or 1
    local life = d.sparkFrames * d.sparkFrameTicks
    for i = #state.sparks, 1, -1 do
        local spark = state.sparks[i]
        spark.age = spark.age + 1
        if spark.age >= life then table.remove(state.sparks, i) end
    end
    state.sparkWait = state.sparkWait - 1
    if state.sparkWait > 0 then return end
    local rolls = {}
    for k = 1, 4 do state.sparkSeed, rolls[k] = cosmeticRoll(state.sparkSeed) end
    local parts = #d.parts
    state.sparks[#state.sparks + 1] = {
        part = math.min(parts, 1 + math.floor(rolls[1] * parts)),
        angle = rolls[2] * 360,
        side = (rolls[3] * 2 - 1) * d.sparkSpread,
        age = 0,
    }
    state.sparkWait = d.sparkGap[1] + math.floor(rolls[4] * (d.sparkGap[2] - d.sparkGap[1] + 1))
end

-- ------------------------------------------------------------------ motion
-- Ease the head's turn velocity toward what the wanted heading asks for, so
-- its direction changes smoothly however suddenly the goal moves.
local function steerHead(state, want, maxTurn, accel)
    local d = ConchBlessing.azureDragon.data
    accel = accel or d.turnAccel
    -- Turn rate is capped by speed so the path never curls tighter than minTurnRadius.
    maxTurn = math.min(maxTurn, math.max(state.speed, d.minSpeed) / d.minTurnRadius)
    local err = wrapAngle(want - state.dir)
    local asked = math.max(-maxTurn, math.min(maxTurn, err * d.turnGain * 6))
    state.turnVel = state.turnVel + math.max(-accel, math.min(accel, asked - state.turnVel))
    state.dir = wrapAngle(state.dir + state.turnVel)
    -- How much of its speed the head keeps: less while its goal is off to the side or behind.
    return d.turnSlowdown + (1 - d.turnSlowdown) * math.max(0, math.cos(err))
end

-- The enemy to hunt: the current prey until the head has run through it;
-- then the enemy passed least recently (never-passed ones first), nearest
-- among equals, so every enemy gets its turn.
-- The enemies other live dragons are going for this update.
local function preyOfOthers(state)
    local frame = Game():GetFrameCount()
    local taken = {}
    for other, seen in pairs(liveStates) do
        if other ~= state and other.prey and frame - seen <= 1 then taken[other.prey] = true end
    end
    return taken
end

-- Keep the current prey; otherwise prefer an enemy no other dragon is after,
-- then the one this dragon passed least recently, then the nearest.
local function choosePrey(state, head)
    local taken = preyOfOthers(state)
    local best, bestTaken, bestPass, bestDistance = nil, math.huge, math.huge, math.huge
    for _, enemy in ipairs(roomEnemies()) do
        local hash = GetPtrHash(enemy)
        if hash == state.prey then return enemy end
        local claimed = taken[hash] and 1 or 0
        local pass = state.passed[hash] or -math.huge
        local distance = enemy.Position:Distance(head)
        if claimed < bestTaken or (claimed == bestTaken and (pass < bestPass
            or (pass == bestPass and distance < bestDistance))) then
            best, bestTaken, bestPass, bestDistance = enemy, claimed, pass, distance
        end
    end
    return best
end

local function updateMotion(familiar, state, player)
    local d = ConchBlessing.azureDragon.data
    -- Reattach only after a real teleport of the player (or a runaway failsafe);
    -- hunting across a big room must not pull the dragon back.
    local jumped = state.playerAt and player.Position:Distance(state.playerAt) > d.teleportStep
    state.playerAt = copyVector(player.Position)
    if jumped or state.head:Distance(player.Position) > d.snapDistance then
        snapTo(state, player.Position)
    end
    state.t = state.t + 1
    local head = state.head
    local prey = not state.passing and choosePrey(state, head)
    local wanted
    if state.passing then
        -- Fly-by: straight on through for a moment before turning for the next.
        steerHead(state, state.dir, d.chaseTurnRate, d.chaseTurnAccel)
        wanted = d.chaseSpeed
        state.passing = state.passing - 1
        if state.passing <= 0 then state.passing = nil end
    elseif prey then
        -- Wave pursuit: the bearing to the enemy plus a slow sine weave.
        local toward = prey.Position - head
        local want = math.atan(toward.Y, toward.X) + math.sin(state.t * d.chaseWeaveRate + state.p2) * d.chaseWeave
        wanted = d.chaseSpeed * steerHead(state, want, d.chaseTurnRate, d.chaseTurnAccel)
        local hash = GetPtrHash(prey)
        if state.prey ~= hash then
            state.prey = hash
            debugLog("dragon hunts %s.%s", tostring(prey.Type), tostring(prey.Variant))
        end
        local reach = d.headReach * scaleFor(player) + d.passReach + (prey.Size or 0)
        if toward:Length() <= reach then
            state.passed[hash], state.prey, state.passing = state.t, nil, d.passTicks
            debugLog("dragon runs through %s.%s", tostring(prey.Type), tostring(prey.Variant))
        end
    else
        state.prey = nil
        local angular, radius = orbitShape(state, state.t)
        -- Orbit as a steering field: head along the circle's tangent, tilted
        -- inward when outside the breathing radius and outward when inside,
        -- plus a slow side-to-side weave. Worked in unsquashed floor space.
        local rel = head - player.Position
        local rx, ry = rel.X, rel.Y / d.orbitSquash
        local r = math.sqrt(rx * rx + ry * ry)
        local phi = r > 0.001 and math.atan(ry, rx) or state.theta
        state.theta = phi
        local miss = r - radius
        local want = phi + (math.pi / 2 + math.atan(miss * d.radialGain))
            + math.sin(state.t * d.weaveRate + state.p2) * d.weave
        want = math.atan(math.sin(want) * d.orbitSquash, math.cos(want))
        -- Left behind, the dragon may turn more sharply and swims faster.
        local hurry = math.min(1, math.max(0, miss) / d.hurryDistance)
        local keep = steerHead(state, want, d.idleTurnRate + (d.hurryTurnRate - d.idleTurnRate) * hurry,
            d.turnAccel * (1 + 1.5 * hurry))
        wanted = (angular * radius + math.max(0, miss) * d.catchUp) * keep
    end
    wanted = math.max(d.minSpeed, math.min(d.maxSpeed, wanted))
    local hunting = state.passing or state.prey
    state.speed = state.speed + (wanted - state.speed) * (hunting and d.chaseSpeedEase or d.speedEase)
    local velocity = Vector(math.cos(state.dir), math.sin(state.dir)) * state.speed
    state.velocity = velocity
    state.head = head + velocity
    -- The dragon owns its position; the invisible entity just follows the head.
    familiar.Position = state.head
    familiar.Velocity = Vector(0, 0)

    pushTrail(state.trail, state.head)
    settle(state, true)
    state.renders = 0
end

-- ------------------------------------------------------------------ callbacks
ConchBlessing.azureDragon.onEvaluateCache = function(_, player, cacheFlag)
    if cacheFlag == CacheFlag.CACHE_FAMILIARS then
        local variant = getVariant()
        if not variant then return end
        -- A zero count removes the last dragon once every copy is gone.
        player:CheckFamiliar(variant, familiarCount(player), player:GetCollectibleRNG(DRAGON_ID),
            Isaac.GetItemConfig():GetCollectible(DRAGON_ID))
    end
end

ConchBlessing.azureDragon.onFamiliarInit = function(_, familiar)
    if familiar.Variant ~= getVariant() then return end
    familiar.EntityCollisionClass = EntityCollisionClass.ENTCOLL_NONE
    familiar.GridCollisionClass = EntityGridCollisionClass.GRIDCOLL_NONE
    -- The entity's own sprite stays empty; the parts are drawn on render.
    familiar:GetSprite():Play("Hidden", true)
    getState(familiar)
end

ConchBlessing.azureDragon.onFamiliarUpdate = function(_, familiar)
    if familiar.Variant ~= getVariant() then return end
    local player = familiar.Player
    if not player then return end
    local state = getState(familiar)
    liveStates[state] = Game():GetFrameCount()
    updateMotion(familiar, state, player)
    updateLightning(familiar, state, player, applyContact(familiar, state, player))
    updateSparks(state)
end

local function getSprites(state)
    if state.sprites ~= nil then return state.sprites or nil end
    local ok, sprites = pcall(function()
        local result = {}
        for _, name in ipairs({ "Head", "Body", "Legs", "Tail", "Shadow", "Spark" }) do
            local sprite = Sprite()
            sprite:Load("gfx/dragon.anm2", true)
            if sprite.IsLoaded and not sprite:IsLoaded() then error("gfx/dragon.anm2 did not load") end
            sprite:SetFrame(name, 0)
            result[name] = sprite
        end
        return result
    end)
    if not ok then
        state.sprites = false
        if not reportedRenderFailure then
            reportedRenderFailure = true
            ConchBlessing.printError("[Azure Dragon] familiar art unavailable: " .. tostring(sprites))
        end
        return nil
    end
    state.sprites = sprites
    return sprites
end

local function isReflectionPass()
    local room = Game():GetRoom()
    return RenderMode and type(room.GetRenderMode) == "function"
        and room:GetRenderMode() == RenderMode.RENDER_WATER_REFLECT
end

-- Animation frame for a part: legs stroke through four poses (the front and
-- hind pairs out of step), the tail tuft flutters between two.
local function partFrame(index, t)
    local d = ConchBlessing.azureDragon.data
    if d.legParts[index] then return (t // d.legFrameTicks + index) % 4 end
    if PART_ANIMATIONS[index] == "Tail" then return (t // d.tailFrameTicks) % 2 end
    return 0
end

-- Height of a part above its shadow: the body rises and dips like a swimmer.
local function partLift(index, time)
    local d = ConchBlessing.azureDragon.data
    return d.flyHeight + d.liftWave * math.sin(time * d.liftRate - index * d.liftStep)
end

ConchBlessing.azureDragon.onFamiliarRender = function(_, familiar, offset)
    if familiar.Variant ~= getVariant() or isReflectionPass() then return end
    local state = familiar:GetData().__ConchDragon
    local sprites = state and getSprites(state)
    if not sprites then return end
    local scale = scaleFor(familiar.Player)
    offset = offset or Vector(0, 0)
    -- The callback's offset already carries the camera scroll and screen
    -- shake, so add it to the render position; WorldToScreen would count the
    -- scroll twice and draw the dragon away from itself in scrolling rooms.
    local toRender = Isaac.WorldToRenderPosition
        and function(at) return Isaac.WorldToRenderPosition(at) + offset end
        or function(at) return Isaac.WorldToScreen(at) end
    -- Render runs twice per update; interpolate the pose so the body glides.
    local alpha = math.min(1, state.renders * 0.5)
    state.renders = state.renders + 1
    local time = state.t - 1 + alpha
    local n = #state.segments
    local screen = {}
    for i = 1, n do
        local prev, cur = state.previous[i], state.segments[i]
        screen[i] = toRender(prev + (cur - prev) * alpha)
    end
    -- Shadows on the floor first (every other part, so they do not pile up).
    local shadow = sprites.Shadow
    shadow:SetFrame("Shadow", 0)
    shadow.Rotation = 0
    for i = n, 1, -1 do
        if i % 2 == 1 or i == n then
            local size = scale * partTaper(i)
            shadow.Scale = Vector(size, size)
            shadow:Render(screen[i])
        end
    end
    -- Then the body, tail first, so the parts nearer the head lie on top
    -- wherever the body crosses itself. Legs go under their body part and
    -- share its pose.
    local d = ConchBlessing.azureDragon.data
    for i = n, 1, -1 do
        local angle = state.prevAngles[i] + wrapAngle(state.angles[i] - state.prevAngles[i]) * alpha
        local size = Vector(scale * partTaper(i), scale * partTaper(i))
        local at = screen[i] - Vector(0, partLift(i, time))
        if d.legParts[i] then
            local legs = sprites.Legs
            legs:SetFrame("Legs", partFrame(i, state.t))
            legs.Scale = size
            orient(legs, angle, state.flips[i])
            legs:Render(at)
        end
        local name = PART_ANIMATIONS[i]
        local sprite = sprites[name]
        sprite:SetFrame(name, name == "Tail" and partFrame(i, state.t) or 0)
        sprite.Scale = size
        orient(sprite, angle, state.flips[i])
        sprite:Render(at)
    end
    -- Sparks of current crackle on top of the body.
    local spark = sprites.Spark
    for _, item in ipairs(state.sparks or {}) do
        local i = item.part
        local heading = state.angles[i] or 0
        local size = scale * partTaper(i)
        local aside = Vector(-math.sin(heading), math.cos(heading)) * (item.side * size)
        spark:SetFrame("Spark", item.age // d.sparkFrameTicks)
        spark.Rotation = item.angle
        spark.Scale = Vector(size, size)
        spark:Render(screen[i] - Vector(0, partLift(i, time)) + aside)
    end
end

local function loadSprite(path, label)
    local ok, sprite = pcall(function()
        local s = Sprite()
        s:Load(path, true)
        if s.IsLoaded and not s:IsLoaded() then error(path .. " did not load") end
        return s
    end)
    if not ok then ConchBlessing.printError("[Azure Dragon] " .. label .. " art unavailable: " .. tostring(sprite)) end
    return ok and sprite or false
end

local function strikeLength()
    local total = 0
    for _, ticks in ipairs(ConchBlessing.azureDragon.data.strikeFrames) do total = total + ticks end
    return total
end

local function strikeFrame(age)
    local elapsed = 0
    for frame, ticks in ipairs(ConchBlessing.azureDragon.data.strikeFrames) do
        elapsed = elapsed + ticks
        if age < elapsed then return frame - 1 end
    end
end

ConchBlessing.azureDragon.onUpdate = function()
    local strikes = ConchBlessing.azureDragon._strikes
    local length = strikeLength()
    for i = #strikes, 1, -1 do
        strikes[i].age = strikes[i].age + 1
        if strikes[i].age >= length then table.remove(strikes, i) end
    end
end

local lightningSprite
ConchBlessing.azureDragon.onRender = function()
    local strikes = ConchBlessing.azureDragon._strikes
    if #strikes == 0 then return end
    if lightningSprite == nil then lightningSprite = loadSprite("gfx/effects/conch_dragon_lightning.anm2", "lightning") end
    if not lightningSprite then return end
    for _, item in ipairs(strikes) do
        local frame = strikeFrame(item.age)
        if frame then
            local shape = item.shape or 1
            lightningSprite:SetFrame(shape == 1 and "Strike" or "Strike" .. shape, frame)
            lightningSprite.FlipX = item.flip == true
            lightningSprite:Render(Isaac.WorldToScreen(item.position))
        end
    end
end

local function clearEffects()
    ConchBlessing.azureDragon._strikes = {}
    enemyCache.frame = -1
end

ConchBlessing.azureDragon.onNewRoom = function()
    clearEffects()
    local variant = getVariant()
    if not variant then return end
    for _, entity in ipairs(Isaac.FindByType(EntityType.ENTITY_FAMILIAR, variant, -1, false, false)) do
        local familiar = entity:ToFamiliar()
        local state = familiar and familiar:GetData().__ConchDragon
        if state then
            -- A new room starts with the dragon on its player.
            local at = familiar.Player and familiar.Player.Position or familiar.Position
            familiar.Position = at
            snapTo(state, at)
            state.struck, state.sparks = {}, {}
        end
    end
end

ConchBlessing.azureDragon.onGameStarted = function()
    clearEffects()
end

ConchBlessing.azureDragon._test = {
    contactDamage = contactDamage,
    lightningDamage = lightningDamage,
    cosmeticRoll = cosmeticRoll,
    updateSparks = updateSparks,
    orbitShape = orbitShape,
    pushTrail = pushTrail,
    sampleTrail = sampleTrail,
    layOut = layOut,
    partFrame = partFrame,
    facesLeft = facesLeft,
    orient = orient,
    steerHead = steerHead,
    partTaper = partTaper,
    partLift = partLift,
    strikeFrame = strikeFrame,
    strikeLength = strikeLength,
}

return ConchBlessing.azureDragon
