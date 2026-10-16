-- 진 (Dragon), God of Weather.
--
-- While any player holds it, it always rains (and the rain is heard, a quiet
-- loop) and the room is dimmed as if under dark clouds (well short of Curse of
-- Darkness). Lightning strikes on its own,
-- whether or not anyone shoots: each holder's tears stat divided by 5 is bolts
-- a second (tears 5 strikes once a second), times the copies held, so copies
-- add up linearly as independent storms.
-- A bolt is aimed at a random enemy and catches it as often as the holder's
-- luck allows (50% at luck 0, 5 points more per luck, always from luck 10);
-- a miss lands just past its reach, where it may still catch another enemy.
-- It hurts every enemy around where it lands for the holder's damage. Each
-- bolt rolls as a quiet small thunder; a full thunderclap, which lights the
-- room for a moment, comes only every few seconds, and a quiet distant rumble
-- rolls now and then for as long as it is held. With two or more copies a bolt may rise as a
-- dragon twister instead (Hush's tear pillar, drawn as a plain sprite): it
-- stays where it rose, pulls enemies in and hurts what it touches every tick.
-- The long dragon familiar this item once summoned is the console-only Azure
-- Dragon (azure_dragon.lua).
local DamageProvenance = require("scripts.lib.damage_provenance")
local Sound = require("scripts.lib.sound_volume")

ConchBlessing.dragon = {}

local DRAGON_ID = Isaac.GetItemIdByName("Dragon")
local THUNDER_SOUND = "Conch Dragon Thunder"
local BOLT_SOUND = "Conch Dragon Bolt"
local TWISTER_SOUND = "Conch Dragon Twister"
local RAIN_SOUND = "Conch Dragon Rain"
local BOLT_PROC_KEY = "dragon_bolt"
local TWISTER_PROC_KEY = "dragon_twister"

ConchBlessing.dragon.data = {
    tearsDivisor = 5,                    -- bolts a second = tears stat / 5 x copies held (tears 5, one copy: once a second)
    boltRadius = 60,                     -- about one and a half tiles, plus the enemy's size
    boltScatter = 40,                    -- a hit lands this close to its enemy at most, so the enemy is caught
    -- Accuracy (user decision 2026-10-13): the chance a strike catches its enemy.
    boltHitBase = 0.5,                   -- at luck 0
    boltHitPerLuck = 0.05,               -- more per point of luck: always from luck 10
    boltHitMin = 0.1,                    -- however low the luck
    boltMissReach = 80,                  -- a miss lands up to this far past the bolt's reach from its enemy
    boltDamageMultiplier = 1,            -- of the holder's damage
    twisterChance = 0.05,                -- with twisterMinCopies or more, a bolt rises as a twister instead
    twisterMinCopies = 2,
    twisterLimit = 5,                    -- most twisters in the room at once
    twisterTicks = 150,                  -- five seconds where it rose
    twisterDamagePercent = 0.05,         -- of the holder's damage, per tick, to every enemy it touches
    twisterReach = 28,                   -- touch reach, plus the enemy's size
    twisterPullRadius = 180,             -- enemies this close are sucked in...
    twisterPull = 4.5,                   -- ...this much faster per tick (half at the edge, 1.5x near the middle)
    twisterBossPull = 0.3,               -- share of the pull a boss feels
    twisterStartTicks = 8, twisterEndTicks = 8,  -- Hush pillar Start/End animations
    -- Leader, strike, flash, second stroke, flicker, thin, fade.
    strikeFrames = { 1, 2, 2, 2, 2, 2, 3 },
    boltShapes = 4,                      -- Strike, Strike2..4: forked, split, spray, swinging
    boltScale = { 0.85, 1.1 },           -- each bolt drawn a little smaller or larger
    scorchTicks = 60,                    -- the burnt patch fades over two seconds
    -- Cue volume x the sample's loudest 50 ms must reach -18 dB or it is lost
    -- under gameplay (tests/test_dragon_weather_contracts.py measures it). The
    -- levels are the user's (2026-10-13): bolt -5 dB, the thunderclap -6 dB, the
    -- twister -6 dB (louder to the ear), the rain -21 dB, the distant rumble 6 dB up too. The samples
    -- are generated that loud so volumes stay <= 1.
    boltVolume = 1.0,                    -- every take sits at -5 dB: -5 dB, every bolt
    boltPitch = { 0.9, 1.1 },            -- a small spread, so repeats never sound identical
    -- A rare bolt stands out, a busy storm stays at boltVolume (user decision
    -- 2026-10-13). The boost needs a volume above 1, which other mods use too;
    -- if the engine ever caps it, rare bolts simply stay at the usual level.
    boltRareBoostDb = 5,                 -- extra for strikes this rare (0 dB in all)...
    boltRareGap = 90,                    -- ...a strike every three seconds or slower
    boltBusyGap = 3,                     -- ten strikes a second or faster play at boltVolume
    thunderVolume = 1.0,                 -- every take sits at -6 dB: -6 dB, at most every thunderGap
    thunderGap = 150,                    -- five seconds between full thunderclaps
    twisterVolume = 1.0,                 -- every take sits at -6 dB: -6 dB, for its whole life
    rainVolume = 0.41,                   -- the loop sits at -13.3 dB: -21 dB, for as long as anyone holds it
    twisterWindGap = 90,                 -- a twister rising within three seconds of the last wind joins it: two winds at most
    flashTicks = 6,                      -- a thunderclap lifts the dark this long
    rumbleVolume = 0.6,                  -- vanilla thunder peaks at -5.5 to -7.4 dB: -10 to -12 dB
    rumblePitch = 0.85,                  -- a little lower, so it sounds far away
    rumbleGap = { 360, 600 },            -- 12-20 s between rumbles (the vanilla samples run 8-13 s)
    rumbleFirst = { 90, 240 },           -- the first one 3-8 s after entering a room
    overcast = 0.32,                     -- veil opacity while held (Curse of Darkness goes much darker)
    rainDrops = 56,
    rainFall = 110,                      -- pixels a drop travels before it lands
    rainSlant = 20,                      -- degrees off vertical: drops fall along their own streak (user, 2026-10-15)
    rainAlpha = 0.5,
}

ConchBlessing.dragon._bolts = {}
ConchBlessing.dragon._scorches = {}
ConchBlessing.dragon._twisters = {}
ConchBlessing.dragon._charge = {}         -- per player: bolts owed, by pointer hash
ConchBlessing.dragon._rumble = { count = 0 }  -- the distant thunder's countdown
ConchBlessing.dragon._sky = { sinceThunder = math.huge, sinceWind = math.huge, sinceStrike = math.huge,
    flash = 0, cracks = 0, bolts = 0 }
local enemyCache = { frame = -1, list = {} }
local reported = {}
local sounds = {}

local function debugLog(format, ...)
    if not (ConchBlessing.Config and ConchBlessing.Config.debugMode) then return end
    ConchBlessing.printDebug("[Dragon] " .. string.format(format, ...))
end

local function reportOnce(key, message)
    if reported[key] then return end
    reported[key] = true
    ConchBlessing.printError("[Dragon] " .. message)
end

local function copies(player)
    return player and player:GetCollectibleNum(DRAGON_ID) or 0
end

-- Cosmetic hash for rain, pitch and the rumble's timing, never gameplay RNG:
-- the same index always gives the same value.
local function hash(i)
    local x = math.sin(i * 12.9898 + 78.233) * 43758.5453
    return x - math.floor(x)
end

-- ------------------------------------------------------------------ pure rules
-- Kept free of engine state so tests and the RNG probe can call them directly.
local function shotsPerSecond(maxFireDelay)
    return 30 / (math.max(0, maxFireDelay or 0) + 1)
end

-- Bolts owed per update: tears stat / tearsDivisor a second for each copy,
-- every copy its own storm, so they add up linearly.
local function boltsPerUpdate(maxFireDelay, count)
    local d = ConchBlessing.dragon.data
    return math.max(0, count or 0) * shotsPerSecond(maxFireDelay) / d.tearsDivisor / 30
end

local function boltDamage(playerDamage)
    return playerDamage * ConchBlessing.dragon.data.boltDamageMultiplier
end

local function twisterTickDamage(playerDamage)
    return playerDamage * ConchBlessing.dragon.data.twisterDamagePercent
end

-- What a bolt becomes for a roll in [0, 1): a twister only with enough copies
-- and while the room has room for one more.
local function rollStrikeKind(roll, count, twisters)
    local d = ConchBlessing.dragon.data
    if count >= d.twisterMinCopies and twisters < d.twisterLimit and roll < d.twisterChance then
        return "twister"
    end
    return "bolt"
end

-- Where a bolt that hits lands for two rolls in [0, 1): up to boltScatter
-- from its enemy, in any direction.
local function scatter(center, angleRoll, distanceRoll)
    local angle = angleRoll * 2 * math.pi
    local distance = distanceRoll * ConchBlessing.dragon.data.boltScatter
    return Vector(center.X + math.cos(angle) * distance, center.Y + math.sin(angle) * distance)
end

-- How loud a bolt plays for the average gap between strikes, in updates: the
-- whole boost at boltRareGap or more, none at boltBusyGap or less, and in
-- between by how many times longer the gap is (log scale).
local function boltVolumeForGap(gap)
    local d = ConchBlessing.dragon.data
    local g = math.max(d.boltBusyGap, math.min(d.boltRareGap, tonumber(gap) or d.boltRareGap))
    local share = math.log(g / d.boltBusyGap) / math.log(d.boltRareGap / d.boltBusyGap)
    return d.boltVolume * 10 ^ (d.boltRareBoostDb * share / 20)
end

-- The chance a strike catches its enemy for the holder's luck: 50% at luck 0,
-- 5 points more per luck, between 10% and 100%.
local function boltHitChance(luck)
    local d = ConchBlessing.dragon.data
    return math.max(d.boltHitMin, math.min(1, d.boltHitBase + d.boltHitPerLuck * (tonumber(luck) or 0)))
end

-- Whether a strike with this roll in [0, 1) catches its enemy.
local function rollHit(roll, luck)
    return roll < boltHitChance(luck)
end

-- Where a bolt that misses lands for two rolls in [0, 1): in a ring just past
-- the bolt's reach from its enemy (the enemy's size included), so it never
-- catches that enemy but may catch another one standing there.
local function missSpot(center, angleRoll, distanceRoll, enemySize)
    local d = ConchBlessing.dragon.data
    local angle = angleRoll * 2 * math.pi
    local distance = d.boltRadius + (enemySize or 0) + 4 + distanceRoll * d.boltMissReach
    return Vector(center.X + math.cos(angle) * distance, center.Y + math.sin(angle) * distance)
end

-- Pull velocity toward a twister: strongest near the middle, nothing past the radius.
local function pullToward(center, position, isBoss)
    local d = ConchBlessing.dragon.data
    local toward = center - position
    local distance = toward:Length()
    if distance <= 1 or distance > d.twisterPullRadius then return Vector(0, 0) end
    local strength = d.twisterPull * (1.5 - distance / d.twisterPullRadius) * (isBoss and d.twisterBossPull or 1)
    return toward:Resized(strength)
end

-- The look of one bolt from its running number: which shape, mirrored or not,
-- and how large. Cosmetic only, so it comes from the hash, not the item RNG.
local function boltLook(index)
    local d = ConchBlessing.dragon.data
    local shape = 1 + math.floor(hash(index * 3 + 1) * d.boltShapes) % d.boltShapes
    local flip = hash(index * 3 + 2) < 0.5
    local scale = d.boltScale[1] + hash(index * 3 + 3) * (d.boltScale[2] - d.boltScale[1])
    return shape, flip, scale
end

-- ------------------------------------------------------------------ enemies
local function isTarget(entity)
    return entity and entity:Exists() and entity:IsVulnerableEnemy() and entity:IsActiveEnemy(false)
        and not entity:IsDead() and not entity:HasEntityFlags(EntityFlag.FLAG_FRIENDLY)
end

-- One room scan per update, shared by every holder and twister.
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

local function soundId(name)
    if sounds[name] == nil then
        local id = Isaac.GetSoundIdByName and Isaac.GetSoundIdByName(name)
        sounds[name] = type(id) == "number" and id > 0 and id or false
        if not sounds[name] then reportOnce(name, "missing sound: " .. name) end
    end
    return sounds[name] or nil
end

-- ------------------------------------------------------------------ strikes
-- Rolls, in order: the enemy, the angle, the distance, then whether it hits.
local function strikePosition(rng, enemies, luck)
    local enemy = enemies[rng:RandomInt(#enemies) + 1]
    local angleRoll, distanceRoll = rng:RandomFloat(), rng:RandomFloat()
    local hit = rollHit(rng:RandomFloat(), luck)
    local room = Game():GetRoom()
    local function inRoom(spot)
        return not (room and room.IsPositionInRoom) or room:IsPositionInRoom(spot, 0)
    end
    if hit then
        local spot = scatter(enemy.Position, angleRoll, distanceRoll)
        return inRoom(spot) and spot or enemy.Position, true
    end
    -- A miss that would leave the room turns to another side of its enemy;
    -- walled in on every side, it lands on the enemy after all.
    for _, turn in ipairs({ 0, 0.5, 0.25, 0.75 }) do
        local spot = missSpot(enemy.Position, angleRoll + turn, distanceRoll, enemy.Size)
        if inRoom(spot) then return spot, false end
    end
    return enemy.Position, true
end

-- Every bolt rolls quietly; a full thunderclap, with a flash, at most every thunderGap.
local function sound(bolts)
    local d = ConchBlessing.dragon.data
    local sky = ConchBlessing.dragon._sky
    sky.cracks = sky.cracks + 1
    -- How busy the storm is: a running average of the gaps between strikes.
    local gap = math.min(sky.sinceStrike, d.boltRareGap * 2)
    sky.gapAverage = sky.gapAverage and (sky.gapAverage + gap) / 2 or gap
    sky.sinceStrike = 0
    if sky.sinceThunder >= d.thunderGap then
        sky.sinceThunder, sky.flash = 0, d.flashTicks
        local id, volume = soundId(THUNDER_SOUND), Sound.volume(d.thunderVolume)
        if id then SFXManager():Play(id, volume, 0, false, 1) end
        return "thunder", volume, sky.gapAverage
    end
    local id = soundId(BOLT_SOUND)
    local volume = Sound.volume(boltVolumeForGap(sky.gapAverage))
    if id then
        SFXManager():Play(id, volume, 0, false, d.boltPitch[1] + hash(sky.cracks) * (d.boltPitch[2] - d.boltPitch[1]))
    end
    return "bolt", volume, sky.gapAverage
end

local function bolt(player, position, enemies, aimed)
    local d = ConchBlessing.dragon.data
    local damage = boltDamage(player.Damage)
    local hit = 0
    DamageProvenance.withTriggeredSource(player, BOLT_PROC_KEY, nil, BOLT_PROC_KEY, function()
        for _, enemy in ipairs(enemies) do
            local limit = d.boltRadius + (enemy.Size or 0)
            if enemy:Exists() and position:DistanceSquared(enemy.Position) <= limit * limit then
                enemy:TakeDamage(damage, 0, EntityRef(player), 0)
                hit = hit + 1
            end
        end
    end)
    local at = Vector(position.X, position.Y)
    local bolts = ConchBlessing.dragon._bolts
    local sky = ConchBlessing.dragon._sky
    sky.bolts = sky.bolts + 1
    local shape, flip, scale = boltLook(sky.bolts)
    bolts[#bolts + 1] = { position = at, age = 0, shape = shape, flip = flip, scale = scale }
    local scorches = ConchBlessing.dragon._scorches
    scorches[#scorches + 1] = { position = at, age = 0 }
    local cue, volume, gap = sound(bolts)
    debugLog("bolt at %.0f,%.0f damage=%.2f hit=%d sound=%s vol=%.2f (%+.1f dB) gap=%.0f aim=%s", position.X, position.Y,
        damage, hit, cue, volume, 20 * math.log(volume, 10), gap, aimed and "on" or "miss")
end

local function raiseTwister(player, position)
    local twisters = ConchBlessing.dragon._twisters
    twisters[#twisters + 1] = { position = Vector(position.X, position.Y), age = 0, player = EntityPtr(player) }
    local d, sky = ConchBlessing.dragon.data, ConchBlessing.dragon._sky
    if sky.sinceWind >= d.twisterWindGap then
        sky.sinceWind = 0
        local id = soundId(TWISTER_SOUND)
        if id then SFXManager():Play(id, Sound.volume(d.twisterVolume), 0, false, 1) end
    end
    debugLog("twister rises at %.0f,%.0f (%d in the room)", position.X, position.Y, #twisters)
end

local function strike(player, count, enemies)
    local rng = player:GetCollectibleRNG(DRAGON_ID)
    local position, aimed = strikePosition(rng, enemies, player.Luck)
    if rollStrikeKind(rng:RandomFloat(), count, #ConchBlessing.dragon._twisters) == "twister" then
        raiseTwister(player, position)
    else
        bolt(player, position, enemies, aimed)
    end
end

-- ------------------------------------------------------------------ twisters
local function updateTwister(twister)
    local d = ConchBlessing.dragon.data
    twister.age = twister.age + 1
    local life = d.twisterTicks + d.twisterEndTicks
    if twister.age >= life then return false end
    if twister.age >= d.twisterTicks then return true end   -- fading out, harmless
    local player = twister.player and twister.player.Ref
    player = player and player:ToPlayer()
    if not player then
        twister.age = d.twisterTicks
        return true
    end
    local damage = twisterTickDamage(player.Damage)
    DamageProvenance.withTriggeredSource(player, TWISTER_PROC_KEY, nil, TWISTER_PROC_KEY, function()
        for _, enemy in ipairs(roomEnemies()) do
            if enemy:Exists() then
                enemy.Velocity = enemy.Velocity + pullToward(twister.position, enemy.Position, enemy:IsBoss())
                local limit = d.twisterReach + (enemy.Size or 0)
                if twister.position:DistanceSquared(enemy.Position) <= limit * limit then
                    enemy:TakeDamage(damage, 0, EntityRef(player), 0)
                end
            end
        end
    end)
    return true
end

-- ------------------------------------------------------------------ rumble
-- Updates until the next distant rumble, spread over [lo, hi] by the hash.
local function rumbleWait(range, index)
    return range[1] + math.floor(hash(index) * (range[2] - range[1] + 1))
end

-- A quiet thunder roll every 12-20 seconds while anyone holds it.
local function updateRumble(held)
    local d = ConchBlessing.dragon.data
    local rumble = ConchBlessing.dragon._rumble
    if not held then rumble.wait = nil; return end
    rumble.wait = rumble.wait or rumbleWait(d.rumbleFirst, rumble.count + 0.5)
    rumble.wait = rumble.wait - 1
    if rumble.wait > 0 then return end
    rumble.count = rumble.count + 1
    rumble.wait = rumbleWait(d.rumbleGap, rumble.count)
    local id = SoundEffect and SoundEffect.SOUND_THUNDER
    if id then SFXManager():Play(id, Sound.volume(d.rumbleVolume), 0, false, d.rumblePitch) end
    debugLog("distant thunder (next in %d updates)", rumble.wait)
end

-- ------------------------------------------------------------------ rain sound
-- The rain loop plays while anyone holds it, across rooms, and stops when
-- nobody does or the game is left. The sound is this item's own, so stopping
-- it touches nothing else. Its level follows the MCM sound and rain settings:
-- a changed setting restarts the loop at the new level, and 0 leaves it off.
local rainLevel -- the volume the playing loop was started at
local function stopRainSound()
    local id = soundId(RAIN_SOUND)
    rainLevel = nil
    if id and SFXManager():IsPlaying(id) then SFXManager():Stop(id) end
end

local function updateRainSound(held)
    if not held then stopRainSound(); return end
    local id = soundId(RAIN_SOUND)
    if not id then return end
    local sfx, volume = SFXManager(), Sound.volume(ConchBlessing.dragon.data.rainVolume, "rain")
    if sfx:IsPlaying(id) and rainLevel ~= volume then sfx:Stop(id) end
    if volume > 0 and not sfx:IsPlaying(id) then
        sfx:Play(id, volume, 0, true, 1)
        rainLevel = volume
    end
end

-- ------------------------------------------------------------------ update
local function strikeLength()
    local total = 0
    for _, ticks in ipairs(ConchBlessing.dragon.data.strikeFrames) do total = total + ticks end
    return total
end

local function strikeFrame(age)
    local elapsed = 0
    for frame, ticks in ipairs(ConchBlessing.dragon.data.strikeFrames) do
        elapsed = elapsed + ticks
        if age < elapsed then return frame - 1 end
    end
end

local function anyHolder()
    local game = Game()
    for i = 0, game:GetNumPlayers() - 1 do
        if copies(Isaac.GetPlayer(i)) > 0 then return true end
    end
    return false
end

local function age(list, length)
    for i = #list, 1, -1 do
        list[i].age = list[i].age + 1
        if list[i].age >= length then table.remove(list, i) end
    end
end

ConchBlessing.dragon.onUpdate = function()
    local d = ConchBlessing.dragon.data
    local game = Game()
    local sky = ConchBlessing.dragon._sky
    sky.sinceThunder = sky.sinceThunder + 1
    sky.sinceWind = sky.sinceWind + 1
    sky.sinceStrike = sky.sinceStrike + 1
    if sky.flash > 0 then sky.flash = sky.flash - 1 end
    local held = false
    local enemies = roomEnemies()
    local charge = ConchBlessing.dragon._charge
    for i = 0, game:GetNumPlayers() - 1 do
        local player = Isaac.GetPlayer(i)
        local count = copies(player)
        local key = GetPtrHash(player)
        if count > 0 then
            held = true
            if #enemies == 0 then
                charge[key] = 0                 -- no bolts are banked between fights
            else
                charge[key] = (charge[key] or 0) + boltsPerUpdate(player.MaxFireDelay, count)
                -- A hair under 1 still counts, so float drift never swallows a bolt.
                while charge[key] >= 1 - 1e-9 do
                    charge[key] = charge[key] - 1
                    strike(player, count, enemies)
                end
            end
        else
            charge[key] = nil
        end
    end
    -- Without REPENTOGON's room render hook there is no veil under the HUD, so
    -- fall back to the engine's own darkening, refreshed every update.
    if held and not ModCallbacks.MC_POST_ROOM_RENDER_ENTITIES and type(game.Darken) == "function" then
        game:Darken(d.overcast, 2)
    end
    updateRumble(held)
    updateRainSound(held)
    local twisters = ConchBlessing.dragon._twisters
    for i = #twisters, 1, -1 do
        if not updateTwister(twisters[i]) then table.remove(twisters, i) end
    end
    age(ConchBlessing.dragon._bolts, strikeLength())
    age(ConchBlessing.dragon._scorches, d.scorchTicks)
end

-- ------------------------------------------------------------------ drawing
local function loadSprite(path, label, animation)
    local ok, sprite = pcall(function()
        local s = Sprite()
        s:Load(path, true)
        if s.IsLoaded and not s:IsLoaded() then error(path .. " did not load") end
        if animation then s:SetFrame(animation, 0) end
        return s
    end)
    if not ok then reportOnce(label, label .. " art unavailable: " .. tostring(sprite)) end
    return ok and sprite or false
end

local art = {}
local function getArt(key, path, animation)
    if art[key] == nil then art[key] = loadSprite(path, key, animation) end
    return art[key] or nil
end

-- The Hush pillar animation and frame for a twister at its age.
local function twisterFrame(twister)
    local d = ConchBlessing.dragon.data
    if twister.age >= d.twisterTicks then return "End", math.min(twister.age - d.twisterTicks, d.twisterEndTicks - 1) end
    if twister.age < d.twisterStartTicks then return "Start", twister.age end
    return "Loop", twister.age % 8
end

-- Opacity of the dark veil: a thunderclap lifts most of it for a moment.
local function veilAlpha(flash)
    local d = ConchBlessing.dragon.data
    return d.overcast * (1 - 0.75 * math.max(0, math.min(1, flash / d.flashTicks)))
end

local function screenSize()
    local width = Isaac.GetScreenWidth and Isaac.GetScreenWidth() or 480
    local height = Isaac.GetScreenHeight and Isaac.GetScreenHeight() or 270
    return width, height
end

local function drawVeil()
    local pixel = getArt("veil", "gfx/effects/conch_upgrade_pixel.anm2", "Idle")
    if not pixel then return end
    local width, height = screenSize()
    pixel.Scale = Vector(width, height)
    pixel.Rotation = 0
    pixel.Color = Color(0.04, 0.05, 0.1, veilAlpha(ConchBlessing.dragon._sky.flash))
    pixel:Render(Vector(0, 0))
end

local RAIN = { 0.69, 0.83, 0.88 }
local function drawRain()
    local d = ConchBlessing.dragon.data
    local pixel = getArt("rain", "gfx/effects/conch_upgrade_pixel.anm2", "Idle")
    if not pixel then return end
    local ripple = getArt("ripple", "gfx/1000.133_water ripple.anm2", "Poof")
    local room = Game():GetRoom()
    local topLeft, bottomRight = room:GetTopLeftPos(), room:GetBottomRightPos()
    local time = Isaac.GetFrameCount() / 60          -- render frames, 60 a second
    for i = 1, d.rainDrops do
        local spot = Vector(topLeft.X + hash(i) * (bottomRight.X - topLeft.X),
            topLeft.Y + hash(i + 100) * (bottomRight.Y - topLeft.Y))
        local period = 0.8 + hash(i + 200) * 0.6
        local p = ((time + hash(i + 300) * period) % period) / period
        local at = Isaac.WorldToScreen(spot)
        if p < 0.7 then
            -- The streak leans rainSlant degrees (top to the right) and the drop
            -- travels along it, so its lower end lands on the ripple's spot.
            local slant = math.rad(d.rainSlant)
            local along = Vector(-math.sin(slant), math.cos(slant))   -- down the streak
            local head = at - along * (d.rainFall * (1 - p / 0.7))
            pixel.Scale = Vector(1, 8)
            pixel.Rotation = d.rainSlant
            pixel.Color = Color(RAIN[1], RAIN[2], RAIN[3], d.rainAlpha)
            pixel:Render(head - along * 8)
        elseif ripple then
            ripple:SetFrame("Poof", math.min(13, math.floor((p - 0.7) * period * 30)))
            ripple.Scale = Vector(0.22, 0.22)
            ripple.Color = Color(1, 1, 1, d.rainAlpha * 0.8)
            ripple:Render(at)
        end
    end
end

local function drawStrikes()
    local d = ConchBlessing.dragon.data
    local scorches, bolts = ConchBlessing.dragon._scorches, ConchBlessing.dragon._bolts
    local lightning = (#scorches > 0 or #bolts > 0) and getArt("lightning", "gfx/effects/conch_dragon_lightning.anm2")
    if lightning then
        -- Burnt patches first, their embers dying, then fading out.
        for _, item in ipairs(scorches) do
            lightning:SetFrame("Scorch", math.min(2, item.age // 10))
            lightning.Color = Color(1, 1, 1, math.min(1, 2 * (1 - item.age / d.scorchTicks)))
            lightning:Render(Isaac.WorldToScreen(item.position))
        end
        lightning.Color = Color(1, 1, 1, 1)
    end
    local twisters = ConchBlessing.dragon._twisters
    if #twisters > 0 then
        local pillar = getArt("pillar", "gfx/1000.096_hushlaser.anm2")
        if pillar then
            for _, twister in ipairs(twisters) do
                pillar:SetFrame(twisterFrame(twister))
                pillar:Render(Isaac.WorldToScreen(twister.position))
            end
        end
    end
    if lightning then
        for _, item in ipairs(bolts) do
            local frame = strikeFrame(item.age)
            if frame then
                local shape = item.shape or 1
                lightning:SetFrame(shape == 1 and "Strike" or "Strike" .. shape, frame)
                lightning.FlipX = item.flip == true
                lightning.Scale = Vector(item.scale or 1, item.scale or 1)
                lightning:Render(Isaac.WorldToScreen(item.position))
            end
        end
        lightning.FlipX = false
        lightning.Scale = Vector(1, 1)
    end
end

-- REPENTOGON draws the weather after the room's entities and before the HUD:
-- the dark veil, then strikes and rain, which stay bright through it.
ConchBlessing.dragon.onRoomRender = function()
    local held = anyHolder()
    if held then drawVeil() end
    drawStrikes()
    if held then drawRain() end
end

-- Without that hook the weather is drawn in the ordinary render pass instead,
-- without the veil (which would cover the HUD there).
ConchBlessing.dragon.onRender = function()
    if ModCallbacks.MC_POST_ROOM_RENDER_ENTITIES then return end
    drawStrikes()
    if anyHolder() then drawRain() end
end

local function clearEffects()
    ConchBlessing.dragon._bolts = {}
    ConchBlessing.dragon._scorches = {}
    ConchBlessing.dragon._twisters = {}
    ConchBlessing.dragon._charge = {}
    ConchBlessing.dragon._rumble.wait = nil      -- a new room waits a few seconds for its first rumble
    ConchBlessing.dragon._sky.flash = 0
    enemyCache.frame = -1
end

ConchBlessing.dragon.onNewRoom = function()
    clearEffects()
end

ConchBlessing.dragon.onPreGameExit = function()
    stopRainSound()
end

ConchBlessing.dragon.onGameStarted = function()
    stopRainSound()
    clearEffects()
end

ConchBlessing.dragon._test = {
    shotsPerSecond = shotsPerSecond,
    boltsPerUpdate = boltsPerUpdate,
    boltDamage = boltDamage,
    twisterTickDamage = twisterTickDamage,
    rollStrikeKind = rollStrikeKind,
    scatter = scatter,
    boltHitChance = boltHitChance,
    boltVolumeForGap = boltVolumeForGap,
    rollHit = rollHit,
    missSpot = missSpot,
    pullToward = pullToward,
    twisterFrame = twisterFrame,
    strikeFrame = strikeFrame,
    strikeLength = strikeLength,
    rumbleWait = rumbleWait,
    veilAlpha = veilAlpha,
    boltLook = boltLook,
}

return ConchBlessing.dragon
