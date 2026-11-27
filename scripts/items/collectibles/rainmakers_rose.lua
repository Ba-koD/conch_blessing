local require = ConchBlessingRequire or require -- reloadable loader, see main.lua
-- 레인메이커의 장미 (Rose of the Rainmaker), the Magic Conch's positive answer
-- to Depression (user design 2026-11-27). The Rainmaker, the Downpour boss
-- that drops Depression, keeps a red rose; this is an homage to the rose of
-- SuddenlySquid's Rainmaker character mod (Workshop 850336061), whose effect
-- the user asked to bring over; its icon is a native 32x32 redraw (2026-11-28).
-- Its rules, read from that mod's Rep/Repmain.lua with the user's leave on
-- 2026-11-27 and written again here:
--   * tears fall from the sky onto random spots of the room: one per copy
--     every three times the holder's fire delay (a third of their tears),
--     fired as the holder's own tears (every tear effect rides along), homing,
--     pale and half transparent, dropped from height 500;
--   * a hit brings down 25 of them at once (the downpour);
--   * shot speed +0.2, once.
-- Differences: a drop comes every 3 x (MaxFireDelay + 1) updates, so the rain
-- is exactly a third of the tears stat (the original used 3 x MaxFireDelay
-- and stopped at one an update); a hit is what `player_hits` counts, so
-- self-damage brings no downpour; dead players and co-op ghosts bring no rain.
-- The rain tears are not aimed, so Live Eye does not score them.
-- Our own additions (user decisions 2026-11-27): while a living player holds
-- 진 (whose rain always falls) the rain falls twice over; and the rain takes
-- the form of the holder's attack, which the original never did (measured
-- 2026-11-27 with `cb test rainmakers_rose weapon_probe`: FireTear gives a
-- plain tear with every weapon). Brimstone raises 진's own twister in red,
-- Technology strikes straight down from above the room's top as a thin beam,
-- Tech X leaves a ring, Dr. Fetus drops a bomb and Epic Fetus a rocket that
-- land as explosions hurting only enemies, and
-- Mom's Knife, Spirit Sword, the Forgotten's bone and C Section fall as blades,
-- sword beams, bones and fetuses. A twister, beam, ring or blast is carried by
-- an invisible, harmless homing drop and strikes where that drop lands or
-- hits, so the rain still homes; a bomb or rocket is drawn where its carrier
-- falls.
local Hits = require("scripts.lib.player_hits")
local Sound = require("scripts.lib.sound_volume")
local M = {}
ConchBlessing.rainmakersRose = M

local ID = Isaac.GetItemIdByName("Rose of the Rainmaker")
local DRAGON = Isaac.GetItemIdByName("Dragon") -- 진, the God of Weather

M.data = {
    share = 3,                -- one drop per copy for every `share` shots' worth of fire delay
    storm = 2,                -- while a living player holds 진 (its rain always falls), the rain falls this many times over
    downpour = 25,            -- drops a hit brings down
    height = -500,            -- where a drop starts, above the floor
    fallingSpeed = 20,
    fallingAcceleration = 2,
    color = { 0.8, 0.8, 1, 0.5 },
    margin = 16,              -- Room:GetRandomPosition's distance from the walls
    shotSpeed = 0.2,
    -- The forms (user decision 2026-11-27); every strike deals the drop's damage.
    beamFall = 80,            -- the shortest a Technology beam gets
    laserAbove = 80,          -- a Technology beam starts this far above the room's top wall (user request
                              -- 2026-11-27: from very high up) and reaches down to where its drop lands
    laserTime = 2,            -- a Technology beam's life
    twisterColor = { 1, 0.25, 0.25, 1, 0.4, 0, 0 },  -- Brimstone: 진's twister, red (user request 2026-11-27)
    ringRadius = 24,          -- a Tech X ring's radius
    ringTime = 12,            -- and its life
    bombRadius = 40, bombScale = 0.6,       -- Dr. Fetus: a small blast
    rocketRadius = 56, rocketScale = 0.85,  -- Epic Fetus: a larger one
    blastVolume = 0.6,
}

-- Marks on a drop's GetData: ours, and not aimed by the player.
M.MARK = "__ConchBlessingRainmakersRose"
M.UNAIMED = "__ConchBlessingUnaimed"
M.CARRIER = "__ConchBlessingRainmakersRoseCarrier"

local progress = {}   -- GetPtrHash(player) -> updates since its last drop
local carriers = {}   -- drops in the air that strike as they land: { ref, x, y, form, owner, damage, born }
local evidence = { rain = 0, downpour = 0, brimstone = 0, laser = 0, ring = 0, bomb = 0, rocket = 0, drawn = 0 }
local soundFrame = -1

-- What the rain becomes with each attack, first match wins (the engine lets
-- some weapons sit together: Epic Fetus over Dr. Fetus over the beams).
local WT = WeaponType or {}
local TV = TearVariant or {}
local FORMS = {}
for _, entry in ipairs({
    { "WEAPON_ROCKETS", { strike = "rocket" } },
    { "WEAPON_BOMBS", { strike = "bomb" } },
    { "WEAPON_TECH_X", { strike = "ring" } },
    { "WEAPON_BRIMSTONE", { strike = "brimstone" } },
    { "WEAPON_LASER", { strike = "laser" } },
    { "WEAPON_KNIFE", { variant = TV.RAZOR, pierce = true } },
    { "WEAPON_SPIRIT_SWORD", { variant = TV.SWORD_BEAM } },
    { "WEAPON_BONE", { variant = TV.BONE } },
    { "WEAPON_FETUS", { variant = TV.FETUS } },
}) do
    local weapon = WT[entry[1]]
    if type(weapon) == "number" then
        entry[2].weapon, entry[2].name = weapon, entry[1]
        FORMS[#FORMS + 1] = entry[2]
    end
end

-- ------------------------------------------------------------------ pure rules
-- Updates between two drops of one copy for a player with this MaxFireDelay:
-- a third of the tears stat, 30 / (MaxFireDelay + 1) shots a second.
local function interval(maxFireDelay)
    local delay = (tonumber(maxFireDelay) or 0) + 1
    return math.max(0.01, M.data.share * delay)
end

-- How many drops a timer of `elapsed` updates owes at `every` updates a drop,
-- and what is left of it.
local function owed(elapsed, every)
    local count = math.floor(elapsed / every)
    return count, elapsed - count * every
end

-- ------------------------------------------------------------------ helpers
local function living(player)
    if not player or player:IsDead() then return false end
    if type(player.IsCoopGhost) == "function" and player:IsCoopGhost() then return false end
    return true
end

local function copies(player)
    if ID <= 0 or not player then return 0 end
    return player:GetCollectibleNum(ID)
end

-- The form the rain takes for this player's attack, or nil for plain tears.
local function formOf(player)
    if not player or type(player.HasWeaponType) ~= "function" then return nil end
    for _, form in ipairs(FORMS) do
        if player:HasWeaponType(form.weapon) then return form end
    end
    return nil
end

-- One drop for this player on a random spot of the room.
local function drop(player, room, form)
    local d = M.data
    local tear = player:FireTear(room:GetRandomPosition(d.margin), Vector(0, 0), false, true, false)
    if not tear then return nil end
    tear.Height = d.height
    tear.FallingSpeed = d.fallingSpeed
    tear.FallingAcceleration = d.fallingAcceleration
    tear:AddTearFlags(TearFlags.TEAR_HOMING)
    tear:SetColor(Color(d.color[1], d.color[2], d.color[3], d.color[4], 0, 0, 0), -1, -1, false, false)
    local data = tear:GetData()
    data[M.MARK] = true
    data[M.UNAIMED] = true
    if form and form.variant and type(tear.ChangeVariant) == "function" then tear:ChangeVariant(form.variant) end
    if form and form.pierce then tear:AddTearFlags(TearFlags.TEAR_PIERCING) end
    if form and form.strike then
        -- An invisible, harmless homing carrier: it strikes where it lands or hits.
        carriers[#carriers + 1] = { ref = EntityPtr(tear), x = tear.Position.X, y = tear.Position.Y,
            form = form.strike, owner = EntityPtr(player), damage = tear.CollisionDamage,
            born = Game():GetFrameCount() }
        tear.CollisionDamage = 0
        tear.TearFlags = TearFlags.TEAR_HOMING
        tear.Visible = false
        data[M.CARRIER] = true
    end
    return tear
end

local function rain(player, count, kind)
    local room = Game():GetRoom()
    local form = formOf(player)
    for _ = 1, count do
        if drop(player, room, form) then evidence[kind] = evidence[kind] + 1 end
    end
end

-- Brimstone: 진's own twister, red, where the drop landed.
local function twister(owner, at)
    local dragon = ConchBlessing.dragon
    if not (dragon and type(dragon.raiseTwister) == "function") then return false end
    local c = M.data.twisterColor
    return dragon.raiseTwister(owner, at, Color(c[1], c[2], c[3], c[4], c[5], c[6], c[7])) == true
end

-- A beam striking straight down from the sky onto `at`, from `fall` above it.
local function beam(owner, at, variant, timeout, damage, fall)
    if not (EntityLaser and type(EntityLaser.ShootAngle) == "function") then return false end
    local from = Vector(at.X, at.Y - fall)
    local laser = EntityLaser.ShootAngle(variant, from, 90, timeout, Vector(0, 0), owner)
    if not laser then return false end
    pcall(function() laser.DisableFollowParent = true end)
    laser.Position = from
    if type(laser.SetMaxDistance) == "function" then laser:SetMaxDistance(fall)
    else laser.MaxDistance = fall end
    laser.CollisionDamage = damage
    laser:GetData()[M.MARK] = true
    return true
end

-- A Tech X ring where the drop landed.
local function ring(owner, at, damage)
    if type(owner.FireTechXLaser) ~= "function" then return false end
    local laser = owner:FireTechXLaser(at, Vector(0, 0), M.data.ringRadius, owner, 1)
    if not laser then return false end
    laser.Timeout = M.data.ringTime
    laser.CollisionDamage = damage
    laser:GetData()[M.MARK] = true
    return true
end

-- A blast that hurts every vulnerable, unfriendly enemy within `radius` and
-- nobody else: the vanilla explosion is only its picture.
local function blast(owner, at, radius, scale, damage)
    local picture = Isaac.Spawn(EntityType.ENTITY_EFFECT, EffectVariant.BOMB_EXPLOSION, 0, at, Vector(0, 0), nil)
    if picture then picture.SpriteScale = Vector(scale, scale) end
    local source = EntityRef(owner)
    for _, entity in ipairs(Isaac.FindInRadius(at, radius + 80, EntityPartition.ENEMY)) do
        if entity:IsVulnerableEnemy() and not entity:HasEntityFlags(EntityFlag.FLAG_FRIENDLY)
            and entity.Position:Distance(at) <= radius + entity.Size then
            entity:TakeDamage(damage, DamageFlag.DAMAGE_EXPLOSION, source, 0)
        end
    end
    local frame = Game():GetFrameCount()
    if frame ~= soundFrame and SoundEffect.SOUND_EXPLOSION_WEAK then
        soundFrame = frame
        SFXManager():Play(SoundEffect.SOUND_EXPLOSION_WEAK, Sound.volume(M.data.blastVolume), 0, false, 1.1)
    end
    return true
end

local function strikeDown(record)
    local owner = record.owner.Ref
    owner = owner and owner:Exists() and owner:ToPlayer() or nil
    if not owner then return end
    local d, at = M.data, Vector(record.x, record.y)
    local done
    if record.form == "brimstone" then
        done = twister(owner, at)
    elseif record.form == "laser" then
        local top = Game():GetRoom():GetTopLeftPos().Y - d.laserAbove
        done = beam(owner, at, LaserVariant and LaserVariant.THIN_RED or 2, d.laserTime, record.damage,
            math.max(d.beamFall, at.Y - top))
    elseif record.form == "ring" then
        done = ring(owner, at, record.damage)
    elseif record.form == "bomb" then
        done = blast(owner, at, d.bombRadius, d.bombScale, record.damage)
    elseif record.form == "rocket" then
        done = blast(owner, at, d.rocketRadius, d.rocketScale, record.damage)
    end
    if done then evidence[record.form] = evidence[record.form] + 1 end
end

-- Carriers that landed or hit something since the last update strike now.
local function settle()
    if #carriers == 0 then return end
    local keep = {}
    for _, record in ipairs(carriers) do
        local tear = record.ref.Ref
        if tear and tear:Exists() and not tear:IsDead() then
            record.x, record.y = tear.Position.X, tear.Position.Y
            keep[#keep + 1] = record
        else
            strikeDown(record)
        end
    end
    carriers = keep
end

-- Whether 진's storm is on: a living player holds 진, whose rain then falls in
-- every room (synergy, user decision 2026-11-27).
local function stormOn(game)
    if DRAGON <= 0 then return false end
    for i = 0, game:GetNumPlayers() - 1 do
        local player = game:GetPlayer(i)
        if player and player:GetCollectibleNum(DRAGON) > 0 and living(player) then return true end
    end
    return false
end

-- ------------------------------------------------------------------ callbacks
function M.onUpdate()
    if ID <= 0 then return end
    settle()
    local game = Game()
    local storm = nil
    for i = 0, game:GetNumPlayers() - 1 do
        local player = game:GetPlayer(i)
        local n = copies(player)
        local hash = player and GetPtrHash(player)
        if n > 0 and living(player) then
            local every = interval(player.MaxFireDelay)
            local count, left = owed((progress[hash] or 0) + 1, every)
            progress[hash] = left
            if count > 0 then
                if storm == nil then storm = stormOn(game) end
                rain(player, count * n * (storm and M.data.storm or 1), "rain")
            end
        elseif hash then
            progress[hash] = nil
        end
    end
end

function M.onEvaluateCache(_, player, flag)
    if flag ~= CacheFlag.CACHE_SHOTSPEED or copies(player) <= 0 then return end
    local stat = ConchBlessing.stats and ConchBlessing.stats.shotSpeed
    if stat and stat.applyAddition then stat.applyAddition(player, M.data.shotSpeed, nil) end
end

-- ------------------------------------------------------------------ drawing
-- A falling bomb (Dr. Fetus) or rocket (Epic Fetus) where its unseen carrier
-- is, at the carrier's height (no target on the floor: user request 2026-11-28).
-- Cosmetic only; the vanilla animations are used in place.
local art = {}
local function sprite(path, animation)
    if art[path] == nil then
        local ok, made = pcall(function()
            local s = Sprite()
            s:Load(path, true)
            s:Play(animation, true)
            return s
        end)
        art[path] = ok and made or false
        if not ok then ConchBlessing.printError("[Rose of the Rainmaker] could not load " .. path) end
    end
    return art[path] or nil
end

local function isReflectionPass()
    local room = Game():GetRoom()
    return RenderMode ~= nil and type(room.GetRenderMode) == "function"
        and room:GetRenderMode() == RenderMode.RENDER_WATER_REFLECT
end

local function drawFalling()
    if #carriers == 0 or isReflectionPass() then return end
    local now = Game():GetFrameCount()
    for _, record in ipairs(carriers) do
        if record.form == "bomb" or record.form == "rocket" then
            -- EntityPtr hands back an Entity: the height lives on the tear.
            local tear = record.ref.Ref
            tear = tear and tear:Exists() and tear:ToTear() or nil
            if tear then
                local ground = Isaac.WorldToScreen(tear.Position)
                local age = now - (record.born or now)
                if record.form == "rocket" then
                    local rocket = sprite("gfx/1000.031_dr. fetus rocket.anm2", "Falling")
                    if rocket then
                        rocket:SetFrame("Falling", age % 2)
                        rocket:Render(ground + Vector(0, tear.Height))
                        evidence.drawn = evidence.drawn + 1
                    end
                else
                    local bomb = sprite("gfx/004.000_bomb.anm2", "Pulse")
                    if bomb then
                        bomb:SetFrame("Pulse", age % 59)
                        bomb:Render(ground + Vector(0, tear.Height))
                        evidence.drawn = evidence.drawn + 1
                    end
                end
            end
        end
    end
end

-- REPENTOGON draws them after the room's entities; without that hook, in the
-- ordinary render pass.
function M.onRoomRender()
    drawFalling()
end

function M.onRender()
    if ModCallbacks and ModCallbacks.MC_POST_ROOM_RENDER_ENTITIES then return end
    drawFalling()
end

-- A new room starts every holder's rain from nothing; drops of the room left
-- strike nowhere.
function M.reset()
    progress = {}
    carriers = {}
end

-- The downpour: a hit the holder really takes brings down the drops at once.
Hits.register("RAINMAKERS_ROSE", function(_, entity, _, flags)
    local player = entity and entity:ToPlayer()
    if not player or copies(player) <= 0 or not living(player) or not Hits.counts(flags) then return end
    rain(player, M.data.downpour, "downpour")
    return true
end)

M._test = {
    interval = interval,
    owed = owed,
    evidence = evidence,
    resetEvidence = function() for key in pairs(evidence) do evidence[key] = 0 end end,
    progress = function() return progress end,
    carriers = function() return carriers end,
    formOf = formOf,
    forms = FORMS,
}

return M
