-- What counts as the player being hit, for every item that reacts to it: the
-- minus trinkets, the Time = series, Time = Money, Tyrfing and Two Faced Penny.
--
-- User rule (2026-10-21): every damage the player really takes is a hit unless
-- it is self-damage, and Sacrifice Room spikes are never a hit. Self-damage is
-- what the engine marks as such: damage without penalties (devil deal chance),
-- fake hits, the IV Bag, damage that only costs red hearts (Razor Blade, Blood
-- Donation Machine), devil deal payments and curse room doors. An own bomb or
-- any other damage is a hit.
--
-- With REPENTOGON only damage that actually landed counts (MC_POST_ENTITY_TAKE_DMG),
-- so a hit Holy Mantle, Kronos or another mod cancels is not one. The base-game
-- fallback sees the hit before it is final.
--
-- Every hit an item counts shows that item's icon, small, above the player's
-- head, so a player can tell the hit was registered. When such an item starts
-- working again (the Time = series after its pause, a floor-watching item on
-- the next floor), the same icon plays the hit's animation backwards in green:
-- it fades in above the head, comes down and sinks into it (user request
-- 2026-11-13).
local Hits = { order = {}, handlers = {}, floor = {}, floorOrder = {} }

local EFFECT_UPDATES = 30
local ICON_SCALE = 0.5
local ICON_SPACING = 14
local HEAD_HEIGHT = 34
local RISE = 8
local POP_UPDATES = 4
local FADE_UPDATES = 12
local ICON_ANM2 = "gfx/005.100_collectible.anm2"

local function damageFlag(name)
    return DamageFlag and DamageFlag[name] or 0
end

local function selfDamageMask()
    return damageFlag("DAMAGE_NO_PENALTIES") | damageFlag("DAMAGE_FAKE") | damageFlag("DAMAGE_IV_BAG")
        | damageFlag("DAMAGE_RED_HEARTS") | damageFlag("DAMAGE_DEVIL") | damageFlag("DAMAGE_CURSED_DOOR")
end

local function toFlags(flags)
    return math.tointeger(tonumber(flags) or 0) or 0
end

local function currentRoomType()
    local room = Game():GetRoom()
    return room and room:GetType() or nil
end

function Hits.isSelfDamage(flags)
    return toFlags(flags) & selfDamageMask() ~= 0
end

-- roomType defaults to the current room; spikes are a hit except in a Sacrifice Room.
function Hits.counts(flags, roomType)
    flags = toFlags(flags)
    if Hits.isSelfDamage(flags) then return false end
    if flags & damageFlag("DAMAGE_SPIKES") ~= 0 then
        if (roomType or currentRoomType()) == RoomType.ROOM_SACRIFICE then return false end
    end
    return true
end

-- handler(_, entity, amount, flags, source, countdown) is the item's own hit
-- handler. It returns true when it counted the hit (its key's icon shows), or a
-- list of ItemData keys to show instead.
function Hits.register(key, handler)
    assert(type(key) == "string" and type(handler) == "function", "Hits.register needs a key and a handler")
    if not Hits.handlers[key] then Hits.order[#Hits.order + 1] = key end
    Hits.handlers[key] = handler
end

-- An item whose condition lasts the floor and breaks on any hit while held
-- (a no-hit floor). On the next floor it plays the green recovery for every
-- player who broke it and still holds it.
function Hits.watchFloor(key)
    if not Hits.floor[key] then
        Hits.floor[key] = true
        Hits.floorOrder[#Hits.floorOrder + 1] = key
    end
end

-- ------------------------------------------------------------------ effect
local effects = {}      -- hits, by player
local recoveries = {}   -- green recoveries, by player
local broken = {}       -- player -> { key = true }: floor watches broken on this floor
local pending = {}      -- player -> { ref, keys }: recoveries waiting for the new floor's room
local sprites = {}
local reportedIconFailure = false

local function iconPath(key)
    local item = ConchBlessing.ItemData and ConchBlessing.ItemData[key]
    if type(item) ~= "table" or type(item.id) ~= "number" or item.id <= 0 then return nil end
    local config = Isaac.GetItemConfig()
    local entry = item.type == "trinket" and config:GetTrinket(item.id) or config:GetCollectible(item.id)
    local gfx = entry and entry.GfxFileName
    return type(gfx) == "string" and gfx ~= "" and gfx or nil
end

local function iconSprite(key)
    if sprites[key] == nil then
        local path = iconPath(key)
        local ok, sprite = pcall(function()
            assert(path, "no item art for " .. key)
            local s = Sprite()
            s:Load(ICON_ANM2, false)
            s:ReplaceSpritesheet(1, path)
            s:LoadGraphics()
            s:SetFrame("Idle", 0)
            assert(s:IsLoaded() and type(s.RenderLayer) == "function", "icon sprite did not load")
            return s
        end)
        sprites[key] = ok and sprite or false
        if not ok and not reportedIconFailure then
            reportedIconFailure = true
            ConchBlessing.printError("[PlayerHits] hit icon unavailable: " .. tostring(sprite))
        end
    end
    return sprites[key] or nil
end

-- Several items counting the same hit (or recovering together) share one
-- row of icons.
local function addEffect(list, player, keys)
    if not player or #keys == 0 then return end
    local hash = GetPtrHash(player)
    local effect = list[hash]
    local frame = Game():GetFrameCount()
    if not effect or effect.start ~= frame then
        effect = { start = frame, keys = {}, seen = {} }
        list[hash] = effect
    end
    for _, key in ipairs(keys) do
        if not effect.seen[key] then
            effect.seen[key] = true
            effect.keys[#effect.keys + 1] = key
        end
    end
end

function Hits.show(player, keys)
    addEffect(effects, player, keys)
end

-- The green, backwards icon: `keys` work again for this player.
function Hits.recover(player, keys)
    addEffect(recoveries, player, keys)
end

function Hits.clearEffects()
    effects, recoveries = {}, {}
end

local function holds(player, key)
    local item = ConchBlessing.ItemData and ConchBlessing.ItemData[key]
    local id = type(item) == "table" and item.id or -1
    if type(id) ~= "number" or id <= 0 then return false end
    if item.type == "trinket" then
        -- held, smelted, or kept in a crab's claws
        return type(player.GetTrinketMultiplier) == "function" and player:GetTrinketMultiplier(id) > 0
            or player:HasTrinket(id)
    end
    return player:HasCollectible(id)
end

-- A new floor: every floor watch a player broke on the last one starts again.
function Hits.onNewLevel()
    local game = Game()
    for i = 0, game:GetNumPlayers() - 1 do
        local player = Isaac.GetPlayer(i)
        local hash = player and GetPtrHash(player)
        local keys = hash and broken[hash]
        if keys then
            local list = {}
            for _, key in ipairs(Hits.floorOrder) do
                if keys[key] and holds(player, key) then list[#list + 1] = key end
            end
            if #list > 0 then pending[hash] = { ref = EntityPtr(player), keys = list } end
        end
    end
    broken = {}
end

-- A continued run starts without the floor's record: an item that knows its
-- own floor was broken (from its save) reports it here.
function Hits.markBroken(player, keys)
    if not player then return end
    local hash = GetPtrHash(player)
    for _, key in ipairs(keys) do
        if Hits.floor[key] then
            broken[hash] = broken[hash] or {}
            broken[hash][key] = true
        end
    end
end

-- Shown on the new floor's first update, after the room is up (a room change
-- clears every effect).
function Hits.onUpdate()
    if not next(pending) then return end
    if Game():IsPaused() then return end
    local waiting = pending
    pending = {}
    for _, entry in pairs(waiting) do
        local player = entry.ref.Ref and entry.ref.Ref:ToPlayer()
        if player and player:Exists() then Hits.recover(player, entry.keys) end
    end
end

local function isReflectionPass()
    local room = Game():GetRoom()
    return RenderMode and type(room.GetRenderMode) == "function"
        and room:GetRenderMode() == RenderMode.RENDER_WATER_REFLECT
end

-- One row of icons at `t` updates into the hit's own animation: a pop with a
-- quick flash that settles to the icon's colour while it rises and fades. A
-- recovery draws the same animation backwards (t runs down to 0) in green,
-- with a faint green left on it the whole way so it never reads as a hit.
local RECOVER_TINT = 0.35
local function drawRow(player, effect, t, recover)
    local pop = math.min(1, (t + 1) / POP_UPDATES)
    local alpha = math.min(1, (EFFECT_UPDATES - t) / FADE_UPDATES)
    local flash = math.max(0, 1 - t / POP_UPDATES / 2)
    local scale = ICON_SCALE * (0.7 + 0.3 * pop)
    local base = Isaac.WorldToScreen(player.Position + player.PositionOffset)
    local y = base.Y - HEAD_HEIGHT * player.SpriteScale.Y - RISE * t / EFFECT_UPDATES
    local width = (#effect.keys - 1) * ICON_SPACING
    local color
    if recover then
        local g = math.max(RECOVER_TINT, flash)
        color = Color(1 - 0.6 * g, 1, 1 - 0.6 * g, alpha, 0, 0.4 * g, 0)
    else
        color = Color(1, 1 - 0.6 * flash, 1 - 0.6 * flash, alpha, 0.4 * flash, 0, 0)
    end
    for i, key in ipairs(effect.keys) do
        local sprite = iconSprite(key)
        if sprite then
            sprite.Scale = Vector(scale, scale)
            sprite.Color = color
            sprite:RenderLayer(1, Vector(base.X - width / 2 + (i - 1) * ICON_SPACING, y))
        end
    end
end

-- The live effect of a player in `list` and its age, or nil once it ended.
local function current(list, hash)
    local effect = list[hash]
    if not effect then return nil end
    local age = Game():GetFrameCount() - effect.start
    if age < 0 or age >= EFFECT_UPDATES then
        list[hash] = nil
        return nil
    end
    return effect, age
end

function Hits.onPlayerRender(_, player)
    if not player or (not next(effects) and not next(recoveries)) then return end
    local hash = GetPtrHash(player)
    local hit, hitAge = current(effects, hash)
    local back, backAge = current(recoveries, hash)
    if not (hit or back) or isReflectionPass() then return end
    if hit then drawRow(player, hit, hitAge, false) end
    if back then drawRow(player, back, EFFECT_UPDATES - 1 - backAge, true) end
end

-- ---------------------------------------------------------------- dispatch
local function dispatch(entity, amount, flags, source, countdown)
    local player = entity and entity:ToPlayer()
    if not player then return end
    local shown = {}
    for _, key in ipairs(Hits.order) do
        local ok, result = pcall(Hits.handlers[key], nil, entity, amount, flags, source, countdown)
        local counted = {}
        if not ok then
            ConchBlessing.printError("[PlayerHits] " .. key .. " hit handler failed: " .. tostring(result))
        elseif type(result) == "table" then
            counted = result
        elseif result then
            counted = { key }
        end
        for _, shownKey in ipairs(counted) do shown[#shown + 1] = shownKey end
    end
    if #Hits.floorOrder > 0 and Hits.counts(flags) then
        local hash = GetPtrHash(player)
        for _, key in ipairs(Hits.floorOrder) do
            if holds(player, key) then
                broken[hash] = broken[hash] or {}
                broken[hash][key] = true
            end
        end
    end
    Hits.show(player, shown)
end

-- Offline item tests load their item modules with a bare ConchBlessing table.
local function on(id, fn, param)
    if type(id) == "number" and type(ConchBlessing.AddCallback) == "function" then
        ConchBlessing:AddCallback(id, fn, param)
    end
end

local applied = ModCallbacks.MC_POST_ENTITY_TAKE_DMG
Hits.appliedDamage = type(applied) == "number"
if Hits.appliedDamage then
    -- No entity-type filter: dispatch returns at once for anything but a player.
    on(applied, function(_, entity, amount, flags, source, countdown)
        dispatch(entity, amount, flags, source, countdown)
    end)
else
    on(ModCallbacks.MC_ENTITY_TAKE_DMG, function(_, entity, amount, flags, source, countdown)
        dispatch(entity, amount, flags, source, countdown)
    end, EntityType and EntityType.ENTITY_PLAYER)
end
on(ModCallbacks.MC_POST_PLAYER_RENDER, Hits.onPlayerRender)
on(ModCallbacks.MC_POST_NEW_ROOM, Hits.clearEffects)
on(ModCallbacks.MC_POST_NEW_LEVEL, Hits.onNewLevel)
on(ModCallbacks.MC_POST_UPDATE, Hits.onUpdate)
-- The floor records end with the run (exit); a continued run's items report
-- their broken floors again at game start (Hits.markBroken), in any order.
on(ModCallbacks.MC_PRE_GAME_EXIT, function()
    Hits.clearEffects()
    broken, pending = {}, {}
end)
on(ModCallbacks.MC_POST_GAME_STARTED, function()
    Hits.clearEffects()
    pending = {}
end)

Hits._test = {
    -- The keys whose icons are showing above this player, or nil.
    shown = function(player)
        local effect = player and effects[GetPtrHash(player)]
        if not effect or Game():GetFrameCount() - effect.start >= EFFECT_UPDATES then return nil end
        return effect.keys
    end,
    -- The keys playing the green recovery above this player, or nil.
    recovering = function(player)
        local effect = player and recoveries[GetPtrHash(player)]
        if not effect or Game():GetFrameCount() - effect.start >= EFFECT_UPDATES then return nil end
        return effect.keys
    end,
    -- Floor watches this player broke on this floor.
    broken = function(player) return player and broken[GetPtrHash(player)] or nil end,
    dispatch = dispatch,
}

return Hits
