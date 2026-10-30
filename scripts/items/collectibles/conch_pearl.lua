local require = ConchBlessingRequire or require -- reloadable loader, see main.lua
-- Conch Pearl (소라 진주), the Magic Conch's Sacred Orb. While any living player
-- holds it, every collectible an item pool draws passes through the pool's own
-- MC_POST_GET_COLLECTIBLE: a quality 0-1 result never appears (the same pool
-- draws again, as Sacred Orb does) and a quality 2 result becomes one of this
-- mod's items 10% of the time for each copy living players hold together (20%
-- with two, at most 100%). Quest items and this mod's own items are left alone.
-- Ten copies make it certain, so from ten it no longer rolls itself: a stacking
-- item stops coming once its copies reach the registry's stackCap.
-- A pool that has run out gives Breakfast, and that Breakfast stays, as it does
-- with Sacred Orb.
-- A replaced item's icon floats over its new pedestal and crumbles into the air
-- so the player sees what it was. It works whatever the MCM Spawn Collectibles
-- setting says: it picks from the registry, not from the pools that setting empties.
local M = {}
ConchBlessing.conchpearl = M

M.data = {
    convertChance = 0.10, -- per copy held: a quality 2 draw becomes one of this mod's items
    maxRedraws = 20,      -- pool draws tried for a quality 0-1 result before Breakfast or ours
}

local ITEM_ID = Isaac.GetItemIdByName("Conch Pearl")
-- What the engine draws once a pool and the treasure pool behind it are empty.
local BREAKFAST = CollectibleType and CollectibleType.COLLECTIBLE_BREAKFAST or 25
-- Our rolls come from the draw's own seed, shifted away from the pool's use of it,
-- so the same draw always gives the same answer and no gameplay RNG is consumed.
local RNG_SHIFT = 35
local COLLECTIBLE_TYPES = { passive = true, active = true, familiar = true }
-- The room types the registry's `pool` field uses, and the item pool each one fills.
local ROOM_POOL_NAMES = {
    ROOM_TREASURE = "POOL_TREASURE", ROOM_SHOP = "POOL_SHOP", ROOM_BOSS = "POOL_BOSS",
    ROOM_SECRET = "POOL_SECRET", ROOM_SUPERSECRET = "POOL_SECRET", ROOM_LIBRARY = "POOL_LIBRARY",
    ROOM_CURSE = "POOL_CURSE", ROOM_DEVIL = "POOL_DEVIL", ROOM_ANGEL = "POOL_ANGEL",
    ROOM_PLANETARIUM = "POOL_PLANETARIUM", ROOM_ULTRASECRET = "POOL_ULTRA_SECRET",
}

local registry -- { own = { [id] = true }, candidates = { ... } }, built once
local drawing = false -- inside our own redraw: those draws are filtered by the outer call
local pending = {} -- conversions waiting for the pickup they were drawn for
local effects = {}
local warned = {}
-- Runtime evidence for conch_test conch_pearl; never saved.
local evidence = { redraws = 0, conversions = 0, fallbacks = 0, emptyPools = 0, lastConversion = nil }

local function warn(key, detail)
    if warned[key] then return end
    warned[key] = true
    ConchBlessing.printError("[ConchPearl] " .. key .. ": " .. tostring(detail))
end

local function debugLog(message)
    if ConchBlessing.Config and ConchBlessing.Config.debugMode then
        ConchBlessing.printDebug("[ConchPearl] " .. message)
    end
end

local function roomPools()
    local map = {}
    for roomName, poolName in pairs(ROOM_POOL_NAMES) do
        local room, pool = RoomType and RoomType[roomName], ItemPoolType and ItemPoolType[poolName]
        if room ~= nil and pool ~= nil then map[room] = pool end
    end
    return map
end

-- The item pools a registry row is listed for (`pool` holds RoomType values or
-- { RoomType, weight = ... } entries).
local function poolsOf(row, map)
    local pools = {}
    local entries = row.pool
    if type(entries) ~= "table" then entries = { entries } end
    for _, entry in ipairs(entries) do
        local room = type(entry) == "table" and entry[1] or entry
        local pool = map[room]
        if pool ~= nil then pools[pool] = true end
    end
    return pools
end

-- Every collectible of this mod, and the released ones it may roll into. Hidden
-- rows (console items, WIP previews, Tyrfing) are never candidates. Sorted by ID
-- so the pick never depends on pairs order.
local function getRegistry()
    if registry then return registry end
    local own, candidates, map = {}, {}, roomPools()
    for key, row in pairs(ConchBlessing.ItemData or {}) do
        if type(row) == "table" and COLLECTIBLE_TYPES[row.type] and type(row.id) == "number" and row.id > 0 then
            own[row.id] = true
            if row.hidden ~= true and row.WorkingNow ~= true and row.console ~= true then
                local cap = row.stackable == true and tonumber(row.stackCap) or nil
                candidates[#candidates + 1] = { id = row.id, key = key, active = row.type == "active",
                    stackable = row.stackable == true, pools = poolsOf(row, map),
                    cap = cap and cap > 0 and math.floor(cap) or nil, shared = row.stackShared == true }
            end
        end
    end
    table.sort(candidates, function(a, b) return a.id < b.id end)
    registry = { own = own, candidates = candidates }
    return registry
end

local function isActingPlayer(player)
    if not player then return false end
    if type(player.IsDead) == "function" and player:IsDead() then return false end
    if type(player.IsCoopGhost) == "function" and player:IsCoopGhost() then return false end
    return true
end

-- Copies every living player holds, counted together: the draw belongs to no one.
function M.copiesHeld()
    if ITEM_ID <= 0 then return 0 end
    local copies = 0
    for index = 0, Game():GetNumPlayers() - 1 do
        local player = Isaac.GetPlayer(index)
        if isActingPlayer(player) then copies = copies + player:GetCollectibleNum(ITEM_ID) end
    end
    return copies
end

function M.isActive() return M.copiesHeld() > 0 end

local function anyoneHolds(id)
    for index = 0, Game():GetNumPlayers() - 1 do
        local player = Isaac.GetPlayer(index)
        if player and player:HasCollectible(id) then return true end
    end
    return false
end

-- Copies of a stacking item as its own effect counts them: every living
-- player's together for a shared count, else the most one living player holds.
local function copiesTowardCap(id, shared)
    local total, most = 0, 0
    for index = 0, Game():GetNumPlayers() - 1 do
        local player = Isaac.GetPlayer(index)
        if isActingPlayer(player) then
            local copies = player:GetCollectibleNum(id)
            total, most = total + copies, math.max(most, copies)
        end
    end
    return shared and total or most
end

-- An active, or an item whose copies add nothing, is left out while anyone
-- holds it; a stacking item is left out once its copies reach its stackCap.
local function excluded(candidate)
    if candidate.active or not candidate.stackable then return anyoneHolds(candidate.id) end
    return candidate.cap ~= nil and copiesTowardCap(candidate.id, candidate.shared) >= candidate.cap
end

-- What a quality 0-1 or 2 draw may become: our items listed for that pool first,
-- else any of ours, leaving out the excluded ones.
function M.candidatesFor(poolType)
    local open, inPool = {}, {}
    for _, candidate in ipairs(getRegistry().candidates) do
        if not excluded(candidate) then
            open[#open + 1] = candidate.id
            if poolType ~= nil and candidate.pools[poolType] then inPool[#inPool + 1] = candidate.id end
        end
    end
    if #inPool > 0 then return inPool end
    return open
end

-- "keep" | "redraw" | "roll" for a drawn item: quest items and ours stay, quality
-- 0-1 is drawn again, quality 2 rolls for one of ours, quality 3-4 stays.
local function classify(quality, quest, own)
    if quest or own then return "keep" end
    if quality <= 1 then return "redraw" end
    if quality == 2 then return "roll" end
    return "keep"
end

-- The quality 2 conversion chance with `copies` held: convertChance each, at most 1.
local function chanceFor(copies)
    return math.min(1, M.data.convertChance * math.max(0, copies or 0))
end

local function converts(roll, chance)
    return roll < chance
end

function M.currentChance() return chanceFor(M.copiesHeld()) end

-- The engine's RNG returns its seed's xorshift as the first value, which for a
-- small seed stays small (sequential seeds 7919*i+13 rolled < 0.1 26% of the
-- time, measured in game 2026-10-28). Mixing the draw seed first keeps the 10%
-- exact whatever seed a caller passes.
local function mixSeed(seed)
    local h = math.floor(tonumber(seed) or 0) & 0xffffffff
    h = ((h ~ (h >> 16)) * 0x85ebca6b) & 0xffffffff
    h = ((h ~ (h >> 13)) * 0xc2b2ae35) & 0xffffffff
    h = h ~ (h >> 16)
    if h == 0 then h = 1 end
    return h
end

-- { quality, quest, own } of a drawn collectible, or nil when it cannot be told.
local function describe(id)
    if type(id) ~= "number" or id <= 0 then return nil end
    local config = Isaac.GetItemConfig():GetCollectible(id)
    if not config or type(config.Quality) ~= "number" then return nil end
    local questTag = ItemConfig and ItemConfig.TAG_QUEST
    if not questTag or type(config.HasTags) ~= "function" then
        warn("QUEST_TAG_UNAVAILABLE", "ItemConfig.TAG_QUEST / HasTags missing; draws are left unchanged")
        return nil
    end
    return { quality = config.Quality, quest = config:HasTags(questTag), own = getRegistry().own[id] == true }
end

-- Draws again from the same pool until a result may appear, and also returns the
-- last item drawn. Our own callback lets these nested draws through; other mods'
-- callbacks still see each one.
local function redraw(poolType, decrease, rng)
    local pool = Game():GetItemPool()
    local last
    drawing = true
    local ok, found = pcall(function()
        for _ = 1, M.data.maxRedraws do
            local seed = rng:Next()
            if seed == 0 then seed = 1 end
            local id = pool:GetCollectible(poolType, decrease, seed)
            last = id
            local info = describe(id)
            if info and classify(info.quality, info.quest, info.own) ~= "redraw" then return id end
        end
        return nil
    end)
    drawing = false
    if not ok then
        warn("REDRAW_FAILED", found)
        return nil
    end
    return found, last
end

-- MC_POST_GET_COLLECTIBLE(selected, poolType, decrease, seed). Returns the ID that
-- appears instead, or nil to keep the pool's choice.
function M.onPostGetCollectible(_, selected, poolType, decrease, seed)
    if drawing then return nil end
    local copies = M.copiesHeld()
    if copies <= 0 then return nil end
    local info = describe(selected)
    if not info then return nil end
    local action = classify(info.quality, info.quest, info.own)
    if action == "keep" then return nil end
    local rng = RNG()
    rng:SetSeed(mixSeed(seed), RNG_SHIFT)
    local result, replaced = selected, selected
    if action == "redraw" then
        evidence.redraws = evidence.redraws + 1
        local found, last = redraw(poolType, decrease, rng)
        if found then
            result, replaced = found, found
            local foundInfo = describe(found)
            action = foundInfo and classify(foundInfo.quality, foundInfo.quest, foundInfo.own) or "keep"
        elseif last == BREAKFAST then
            -- The pool ran out before it gave anything but quality 0-1: Breakfast
            -- appears, as with Sacred Orb (user decision 2026-10-31).
            evidence.emptyPools = evidence.emptyPools + 1
            debugLog("empty pool " .. tostring(poolType) .. ": Breakfast stays")
            if selected == BREAKFAST then return nil end
            return BREAKFAST
        else
            -- The pool kept giving quality 0-1: one of ours appears instead.
            action = "fallback"
        end
        debugLog("redraw " .. tostring(selected) .. " -> " .. tostring(found) .. " pool=" .. tostring(poolType))
    end
    if action == "fallback" or (action == "roll" and converts(rng:RandomFloat(), chanceFor(copies))) then
        local list = M.candidatesFor(poolType)
        if #list > 0 then
            local id = list[rng:RandomInt(#list) + 1]
            if decrease then
                -- Like any item that appears, it leaves the natural pools.
                pcall(function() Game():GetItemPool():RemoveCollectible(id) end)
            end
            pending[#pending + 1] = { id = id, replaced = replaced }
            evidence.conversions = evidence.conversions + 1
            if action == "fallback" then evidence.fallbacks = evidence.fallbacks + 1 end
            evidence.lastConversion = { id = id, replaced = replaced, pool = poolType, decrease = decrease == true }
            debugLog("convert " .. tostring(replaced) .. " -> " .. tostring(id) .. " pool=" .. tostring(poolType)
                .. " decrease=" .. tostring(decrease))
            return id
        end
    end
    if result ~= selected then return result end
    return nil
end

-- ------------------------------------------------------------------ dust visual
-- The replaced item's icon rises over the new pedestal, holds a moment, then
-- crumbles from the top into 2x2 grains that drift up and fade. Cosmetic only:
-- ticks advance in MC_POST_UPDATE (so it freezes while paused) and nothing reads
-- them back.
local DUST = {
    ANM2 = "gfx/005.100_collectible.anm2", ANIMATION = "PlayerPickup",
    APPEAR = 10, HOLD = 40, CRUMBLE = 16, FLIGHT = 22, FLIGHT_JITTER = 8,
    FLOAT_DISTANCE = 6, FLOAT_JITTER = 10, SPREAD = 2.2, RISE = 18,
    ICON_SIZE = 32, GRAIN = 2, ICON_Y = -64, PITCH = 28, MAX_ICONS = 4, MAX_EFFECTS = 8,
}
DUST.TOTAL = DUST.APPEAR + DUST.HOLD + DUST.CRUMBLE + DUST.FLIGHT + DUST.FLIGHT_JITTER

-- Cosmetic jitter from an integer hash, never math.random or game RNG.
local function noise(seed, i, j, salt)
    local h = (seed ~ (i * 374761393) ~ (j * 668265263) ~ (salt * 2246822519)) & 0x7fffffff
    h = ((h ~ (h >> 13)) * 1274126177) & 0x7fffffff
    return (h ~ (h >> 16)) / 0x7fffffff
end

local function buildGrains(seed)
    local grains, half, cells = {}, DUST.ICON_SIZE / 2, DUST.ICON_SIZE // DUST.GRAIN
    for j = 0, cells - 1 do
        for i = 0, cells - 1 do
            local cx, cy = DUST.GRAIN * i + DUST.GRAIN / 2, DUST.GRAIN * j + DUST.GRAIN / 2
            local r1, r2, r3 = noise(seed, i, j, 1), noise(seed, i, j, 2), noise(seed, i, j, 3)
            local angle = math.atan(cy - half, cx - half) + (r2 - 0.5) * 1.4
            local distance = DUST.FLOAT_DISTANCE + r3 * DUST.FLOAT_JITTER
            grains[#grains + 1] = {
                hx = cx - half, hy = cy - half,
                -- PlayerPickup draws the icon at (0, -8) with a centred pivot.
                ox = cx - half, oy = cy - half - 8,
                fx = math.cos(angle) * distance, fy = (math.sin(angle) - 0.6) * distance,
                delay = j / (cells - 1) * DUST.CRUMBLE * 0.65 + r1 * DUST.CRUMBLE * 0.35,
                flight = DUST.FLIGHT + r2 * DUST.FLIGHT_JITTER,
                sparkle = r3 > 0.9,
                topLeft = Vector(DUST.GRAIN * i, DUST.GRAIN * j),
                bottomRight = Vector(DUST.ICON_SIZE - DUST.GRAIN * (i + 1), DUST.ICON_SIZE - DUST.GRAIN * (j + 1)),
            }
        end
    end
    return grains
end

local function newIcon(itemId, seed)
    local config = Isaac.GetItemConfig():GetCollectible(itemId)
    local gfx = config and config.GfxFileName
    if type(gfx) ~= "string" or gfx == "" then return nil end
    local sprite = Sprite()
    sprite:Load(DUST.ANM2, false)
    sprite:ReplaceSpritesheet(1, gfx)
    sprite:LoadGraphics()
    sprite:SetFrame(DUST.ANIMATION, 0)
    return { sprite = sprite, itemId = itemId, grains = buildGrains(seed) }
end

-- A question-mark pedestal must not hint at its item. Without REPENTOGON's
-- IsBlind (left out so the item needs no extender) an alternate-path treasure
-- room cannot be told apart, so it shows nothing there.
local function isBlindPedestal(pickup)
    local game = Game()
    local level = game:GetLevel()
    if LevelCurse and LevelCurse.CURSE_OF_BLIND
        and (level:GetCurses() & LevelCurse.CURSE_OF_BLIND) ~= 0 and not pickup.Touched then
        return true
    end
    local stageType = level:GetStageType()
    return game:GetRoom():GetType() == RoomType.ROOM_TREASURE
        and (stageType == StageType.STAGETYPE_REPENTANCE or stageType == StageType.STAGETYPE_REPENTANCE_B)
end

local function attach(pickup)
    if #pending == 0 or not pickup or pickup.Variant ~= PickupVariant.PICKUP_COLLECTIBLE then return end
    local entries = pending
    pending = {}
    local replaced = {}
    for _, entry in ipairs(entries) do
        if entry.id == pickup.SubType and #replaced < DUST.MAX_ICONS then replaced[#replaced + 1] = entry.replaced end
    end
    if #replaced == 0 or #effects >= DUST.MAX_EFFECTS or isBlindPedestal(pickup) then return end
    local seed = (pickup.InitSeed or 0) & 0x7fffffff
    local icons = {}
    for k, itemId in ipairs(replaced) do
        local ok, icon = pcall(newIcon, itemId, seed + k * 7919)
        if ok and icon then icons[#icons + 1] = icon end
    end
    if #icons == 0 then return end
    local position = pickup.Position
    effects[#effects + 1] = { ref = EntityPtr(pickup), x = position.X, y = position.Y, icons = icons, tick = 0 }
end

function M.onPickupInit(_, pickup)
    attach(pickup)
end

function M.onUpdate()
    -- A conversion not claimed by the pickup drawn for it (a Lemegeton wisp, a
    -- cycle choice, a preview draw) has no pedestal to show over.
    if #pending > 0 then pending = {} end
    local i = 1
    while i <= #effects do
        local effect = effects[i]
        effect.tick = effect.tick + 1
        if effect.tick >= DUST.TOTAL then table.remove(effects, i) else i = i + 1 end
    end
end

local function easeOut(x) return 1 - (1 - x) * (1 - x) end

local INTACT = Color(1, 1, 1, 1, 0, 0, 0)

local function renderEffect(effect)
    local ref = effect.ref and effect.ref.Ref
    if ref and ref:Exists() then effect.x, effect.y = ref.Position.X, ref.Position.Y end
    local base = Isaac.WorldToScreen(Vector(effect.x, effect.y))
    local cy = math.max(18, base.Y + DUST.ICON_Y)
    local count = #effect.icons
    local t = effect.tick
    if t < DUST.APPEAR + DUST.HOLD then
        local a = math.min(1, t / DUST.APPEAR)
        local scale = 0.4 + 0.6 * easeOut(a)
        local bob = t > DUST.APPEAR and math.sin((t - DUST.APPEAR) * 0.6) or 0
        for k, icon in ipairs(effect.icons) do
            local cx = base.X + (k - (count + 1) / 2) * DUST.PITCH
            icon.sprite.Scale = Vector(scale, scale)
            icon.sprite.Color = Color(1, 1, 1, a, 0, 0, 0)
            icon.sprite:Render(Vector(cx, cy + 8 * scale + bob))
        end
        return
    end
    local s = t - DUST.APPEAR - DUST.HOLD
    for k, icon in ipairs(effect.icons) do
        local sprite = icon.sprite
        sprite.Scale = Vector.One
        local cx = base.X + (k - (count + 1) / 2) * DUST.PITCH
        for _, grain in ipairs(icon.grains) do
            local u = s - grain.delay
            if u < grain.flight then
                local x, y = cx + grain.hx, cy + grain.hy
                if u <= 0 then
                    sprite.Color = INTACT
                else
                    local p = u / grain.flight
                    local e = easeOut(p)
                    x = x + grain.fx * e * DUST.SPREAD
                    y = y + grain.fy * e * DUST.SPREAD - DUST.RISE * p
                    local glow = 0.3 + 0.5 * p + (grain.sparkle and 0.4 or 0)
                    sprite.Color = Color(1, 1, 1, (1 - p) ^ 1.5, glow * 0.6, glow * 0.5, glow * 0.55)
                end
                sprite:Render(Vector(x - grain.ox, y - grain.oy), grain.topLeft, grain.bottomRight)
            end
        end
    end
end

function M.onRender()
    for _, effect in ipairs(effects) do renderEffect(effect) end
end

-- A room's own pedestals are drawn while it loads, before MC_POST_NEW_ROOM, so
-- a new room keeps the effects whose pedestal is still there and drops the
-- previous room's.
function M.onNewRoom()
    pending, drawing = {}, false
    local kept = {}
    for _, effect in ipairs(effects) do
        local ref = effect.ref and effect.ref.Ref
        if ref and ref:Exists() then kept[#kept + 1] = effect end
    end
    effects = kept
end

-- Game start, exit and unload drop every runtime record.
function M.reset()
    pending, effects, drawing = {}, {}, false
end

M._test = {
    classify = classify,
    converts = converts,
    chanceFor = chanceFor,
    mixSeed = mixSeed,
    describe = describe,
    getRegistry = getRegistry,
    copiesTowardCap = copiesTowardCap,
    DUST = DUST,
    effects = function() return effects end,
    pending = function() return pending end,
    evidence = function() return evidence end,
    resetEvidence = function()
        evidence.redraws, evidence.conversions, evidence.fallbacks, evidence.emptyPools = 0, 0, 0, 0
        evidence.lastConversion = nil
    end,
    -- The registry is static for a session; offline tests rebuild it between cases.
    resetRegistry = function() registry = nil end,
}

return M
