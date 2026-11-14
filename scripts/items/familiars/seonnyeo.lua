-- 선녀 (Seonnyeo): the Magic Conch's positive answer to Succubus (user design
-- 2026-11-13). A heavenly maiden roams the room the way Succubus does. While
-- her owner stands in her golden light their tears are x1.5, and lights that
-- overlap multiply with no cap (two: x2.25). Like Succubus's aura her light
-- hurts the enemies in it on a fixed tick, but by her owner's fire rate
-- rather than a fixed 2.5: each tick deals their tears (shots a second), so
-- it grows with every light they stand in. She gives no damage multiplier,
-- so she is her own familiar rather than the vanilla Succubus entity, which
-- would add Succubus's x1.5 damage. Her light is the vanilla Censer/Succubus
-- halo drawn in gold by her anm2; its radius here is that halo's visible edge.
-- She moves and ticks as the real Succubus does (measured with `cb test
-- seonnyeo succubus_probe`, 2026-11-13). Kronos may absorb her like Succubus:
-- her light then stays on its holder, drawn as the halo alone (no stand-in
-- familiar), for each copy absorbed.
local M = {}
ConchBlessing.seonnyeo = M

local ITEM_ID = Isaac.GetItemIdByName("Seonnyeo")

M.data = {
    tears = 1.5,      -- per light the owner stands in; lights multiply
    -- world units: the halo (`censer halo.png`, drawn at 100%) fades to half
    -- at 87 px, and a 40-unit grid cell is 26 px on screen
    radius = 87 * 40 / 26,
    -- BFFS draws familiars, her halo included, a quarter larger and widens
    -- the light's damage by as much, but not the tears it gives, as with
    -- Succubus (EID: the damaging aura grows, the damage-up aura does not)
    bffsScale = 1.25,
    -- Succubus, measured 2026-11-13: a steady 4.7 units an update in straight
    -- lines 32-45 degrees off the horizontal, out to the walls, a new angle in
    -- that range after each bounce, turning over two or three updates
    speed = 4.7,
    -- the engine's own Succubus movement, `EntityFamiliar:MoveDiagonally`:
    -- at 1 she moves exactly as Succubus (measured 2026-11-13 with `cb test
    -- seonnyeo diagonal_probe`: 4.71 an update, 35-45 degrees, turning 7-9
    -- units from the walls), so Succubus calls it with 1
    engineSpeed = 1,
    minAngle = 30,
    maxAngle = 46,
    -- she turns 8 units inside the room's edge (Succubus turned 5-8 in), so
    -- her 7-unit body never meets the wall, which would slow her
    margin = 8,
    turn = 0.5,       -- share of the way to the new heading taken each update
    -- her light hurts the enemies in it every `tick` updates for the owner's
    -- tears (shots a second) x `perTears`. Succubus's aura ticks 2.5 every 7
    -- updates, the same with BFFS (measured), so BFFS only widens hers
    tick = 7,
    perTears = 1.0,
}

local function variant()
    local data = ConchBlessing.ItemData.SEONNYEO
    return data and data.entity and data.entity.variant
end

-- -------------------------------------------------------------- familiar

function M.onEvaluateCache(_, player, flag)
    if flag ~= CacheFlag.CACHE_FAMILIARS or ITEM_ID <= 0 then return end
    local v = variant()
    if not v then return end
    local count = player:GetCollectibleNum(ITEM_ID) + player:GetEffects():GetCollectibleEffectNum(ITEM_ID)
    player:CheckFamiliar(v, count, player:GetCollectibleRNG(ITEM_ID), Isaac.GetItemConfig():GetCollectible(ITEM_ID))
end

-- A heading `minAngle`-`maxAngle` degrees off the horizontal, going the way
-- `sx`, `sy` say (+1 or -1), as Succubus picks after each bounce. The angle
-- comes from the maiden's own seed, her age and her place among her owner's
-- familiars (every familiar of one owner shares an InitSeed): cosmetic
-- pathing, no gameplay RNG.
local function heading(familiar, sx, sy)
    local rng = RNG()
    rng:SetSeed(math.max(1, (familiar.InitSeed + GetPtrHash(familiar) + familiar.FrameCount * 7919) % 4294967295), 35)
    if not sx then sx = rng:RandomInt(2) == 0 and -1 or 1 end
    if not sy then sy = rng:RandomInt(2) == 0 and -1 or 1 end
    local angle = math.rad(M.data.minAngle + rng:RandomFloat() * (M.data.maxAngle - M.data.minAngle))
    return Vector(sx * math.cos(angle), sy * math.sin(angle)) * M.data.speed
end

local AIM = "__ConchBlessingSeonnyeoAim"

function M.onFamiliarInit(_, familiar)
    if familiar.Variant ~= variant() then return end
    familiar.GridCollisionClass = EntityGridCollisionClass.GRIDCOLL_WALLS
    familiar:GetSprite():Play("Float", true)
    familiar.Velocity = heading(familiar)
    familiar:GetData()[AIM] = familiar.Velocity
end

-- Straight lines at a steady pace like Succubus: the next step is tried along
-- each axis, an axis that would leave the room turns back and a new angle is
-- picked, and she eases onto the new heading over a couple of updates. This
-- copy of Succubus's movement serves only where the engine's own
-- (`EntityFamiliar:MoveDiagonally`, which `engineSpeed` drives) is missing.
local function drift(familiar)
    local room = Game():GetRoom()
    local data = familiar:GetData()
    local aim = data[AIM]
    if not aim or aim:Length() < 0.1 then aim = heading(familiar) end
    local at, margin = familiar.Position, M.data.margin
    local sx, sy = aim.X < 0 and -1 or 1, aim.Y < 0 and -1 or 1
    local bounced = false
    if not room:IsPositionInRoom(Vector(at.X + aim.X, at.Y), margin) then sx, bounced = -sx, true end
    if not room:IsPositionInRoom(Vector(at.X, at.Y + aim.Y), margin) then sy, bounced = -sy, true end
    if bounced then aim = heading(familiar, sx, sy) end
    data[AIM] = aim
    local velocity = familiar.Velocity
    velocity = velocity + (aim - velocity) * M.data.turn
    if velocity:Length() < 0.1 then velocity = aim end
    velocity = velocity:Resized(M.data.speed)
    -- never step out of the room while turning
    if not room:IsPositionInRoom(at + velocity, margin) then velocity = aim end
    familiar.Velocity = velocity
end

function M.onFamiliarUpdate(_, familiar)
    if familiar.Variant ~= variant() then return end
    local speed = M.data.engineSpeed
    speed = M._test and M._test.diagonal or speed -- dev-only
    if speed and type(familiar.MoveDiagonally) == "function" then
        familiar:MoveDiagonally(speed)
    else
        drift(familiar)
    end
    -- she stays upright like the vanilla familiars (user request 2026-11-13:
    -- the lean into her drift is gone); one leaned by an older build straightens
    if familiar.SpriteRotation ~= 0 then familiar.SpriteRotation = 0 end
    local sprite = familiar:GetSprite()
    if not sprite:IsPlaying("Float") then sprite:Play("Float", true) end
    if familiar.FrameCount % M.data.tick == 0 then M.hurt(familiar) end
end

-- ------------------------------------------------------------------- light

-- How far her light's tears reach (BFFS leaves this, as with Succubus).
function M.radius()
    return M.data.radius
end

-- How far her light's damage reaches: BFFS widens it a quarter.
function M.damageRadius(owner)
    local bffs = owner and owner:HasCollectible(CollectibleType.COLLECTIBLE_BFFS)
    return M.data.radius * (bffs and M.data.bffsScale or 1)
end

-- How many of `player`'s maidens' lights reach where they stand.
function M.lightsOver(player, maidens)
    local key, n = GetPtrHash(player), 0
    for _, entity in ipairs(maidens) do
        local familiar = entity:ToFamiliar()
        if familiar and familiar:Exists() and familiar.Player and GetPtrHash(familiar.Player) == key
            and player.Position:Distance(familiar.Position) <= M.radius(familiar) then
            n = n + 1
        end
    end
    return n
end

-- What one tick of a light deals: its owner's tears (shots a second) x
-- perTears.
function M.tickDamage(owner)
    if not owner then return 0 end
    return 30 / (owner.MaxFireDelay + 1) * M.data.perTears
end

-- Every enemy within `radius` of `centre` takes `lights` ticks from `source`.
local function strike(owner, centre, radius, source, lights)
    if not owner or owner:IsDead() or lights <= 0 then return end
    local damage = M.tickDamage(owner) * lights
    if damage <= 0 then return end
    for _, entity in ipairs(Isaac.FindInRadius(centre, radius, EntityPartition.ENEMY)) do
        if entity:IsVulnerableEnemy() and entity:IsActiveEnemy(false)
            and not entity:HasEntityFlags(EntityFlag.FLAG_FRIENDLY)
            and entity.Position:Distance(centre) <= radius then
            entity:TakeDamage(damage, 0, source, 0)
        end
    end
end

-- Every enemy her light reaches takes one tick, with her as the source.
function M.hurt(familiar)
    strike(familiar.Player, familiar.Position, M.damageRadius(familiar.Player), EntityRef(familiar), 1)
end

-- ----------------------------------------------------- Kronos keeps her light

-- How many of her lights Kronos (or Thurisaz) keeps on `player`. Read once
-- per game frame and player: the update and every render of that frame
-- share it (Kronos's count reads run saves).
local keptFrame, keptCache = -1, {}
function M.absorbed(player)
    local kronos = ConchBlessing.kronos
    if ITEM_ID <= 0 or not kronos or type(kronos._getEffectCount) ~= "function" then return 0 end
    local frame = Game():GetFrameCount()
    if frame ~= keptFrame then keptFrame, keptCache = frame, {} end
    local key = GetPtrHash(player)
    local kept = keptCache[key]
    if kept == nil then
        kept = math.max(0, kronos._getEffectCount(player, ITEM_ID) or 0)
        keptCache[key] = kept
    end
    return kept
end

function M.multiplier(n)
    return n > 0 and M.data.tears ^ n or nil
end

-- The multiplier last set on each player (false: none). StatsAPI is only read
-- and written when it changes; the record is dropped at game start and on
-- every new room, so each room starts by checking StatsAPI's own row once (a
-- Continue, a reload or a lost item can leave one behind).
local applied = {}

local function apply(player, n)
    local target = M.multiplier(n)
    local key = GetPtrHash(player)
    if applied[key] == (target or false) then return end
    local um = ConchBlessing.stats and ConchBlessing.stats.unifiedMultipliers
    if not um then return end
    local state = ConchBlessing.getUnifiedMultiplierState(player, um)
    local row = state and state.itemMultipliers and state.itemMultipliers[ITEM_ID]
    local entry = row and row.Tears
    local moved = false
    if target and (not entry or math.abs(entry.value - target) > 1e-9) then
        um:SetItemMultiplier(player, ITEM_ID, "Tears", target, "Seonnyeo")
        moved = true
    elseif not target and entry then
        um:RemoveItemMultiplier(player, ITEM_ID, "Tears")
        moved = true
    end
    if moved then
        if um.QueueCacheUpdate then um:QueueCacheUpdate(player, "Tears") end
        if um.SaveToSaveManager then um:SaveToSaveManager(player) end
    end
    applied[key] = target or false
end

function M.onUpdate()
    local v = variant()
    if not v or ITEM_ID <= 0 then return end
    local maidens = Isaac.FindByType(EntityType.ENTITY_FAMILIAR, v)
    local game = Game()
    for i = 0, game:GetNumPlayers() - 1 do
        local player = game:GetPlayer(i)
        local kept = M.absorbed(player)
        local n = (#maidens > 0 and M.lightsOver(player, maidens) or 0) + kept
        apply(player, n)
        -- the kept lights stay on the player and tick there, the player the source
        if kept > 0 and player.FrameCount % M.data.tick == 0 then
            strike(player, player.Position, M.damageRadius(player), EntityRef(player), kept)
        end
    end
end

-- The kept lights are drawn as the halo alone, under the player: one halo,
-- deeper for each light kept (at most three drawn).
local halo
local function haloSprite()
    if not halo then
        halo = Sprite()
        halo:Load("gfx/seonnyeo.anm2", true)
        halo:SetFrame("Float", 0)
    end
    return halo
end

function M.onPlayerRender(_, player, offset)
    if ITEM_ID <= 0 or Game():GetRoom():GetRenderMode() == RenderMode.RENDER_WATER_REFLECT then return end
    -- Hemispatial Neglect drawing the player again into its capture
    local neglect = ConchBlessing.hemispatialneglect
    if neglect and neglect.isCapturing and neglect.isCapturing() then return end
    local kept = M.absorbed(player)
    if kept <= 0 then return end
    local sprite = haloSprite()
    local scale = player:HasCollectible(CollectibleType.COLLECTIBLE_BFFS) and M.data.bffsScale or 1
    sprite.Scale = Vector(scale, scale)
    -- The render offset is the camera's scroll: it goes with the render
    -- position, never with WorldToScreen, which already holds the scroll (in a
    -- scrolling room the halo then stood still on screen while Isaac walked
    -- on; user report 2026-11-13).
    local at = Isaac.WorldToRenderPosition and (Isaac.WorldToRenderPosition(player.Position) + (offset or Vector.Zero))
        or Isaac.WorldToScreen(player.Position)
    for _ = 1, math.min(kept, 3) do sprite:RenderLayer(1, at) end
end

do
    local callback = ModCallbacks.MC_PRE_PLAYER_RENDER or ModCallbacks.MC_POST_PLAYER_RENDER
    ConchBlessing:AddCallback(callback, M.onPlayerRender)
end

-- On entering a room she is beside her owner; she sets off on a new heading.
function M.onNewRoom()
    applied = {}
    local v = variant()
    if not v then return end
    for _, entity in ipairs(Isaac.FindByType(EntityType.ENTITY_FAMILIAR, v)) do
        local familiar = entity:ToFamiliar()
        if familiar then
            familiar.Velocity = heading(familiar)
            familiar:GetData()[AIM] = familiar.Velocity
        end
    end
end

-- A multiplier saved before (a Continue, another run) is checked once.
function M.onGameStarted()
    applied, keptFrame, keptCache = {}, -1, {}
end

M._test = {
    itemId = function() return ITEM_ID end,
    variant = variant,
    diagonal = nil, -- a bench sets it to drive MoveDiagonally with this value
}

return M
