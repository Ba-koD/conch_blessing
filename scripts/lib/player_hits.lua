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
-- head, so a player can tell the hit was registered.
local Hits = { order = {}, handlers = {} }

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

-- ------------------------------------------------------------------ effect
local effects = {}
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

function Hits.show(player, keys)
    if not player or #keys == 0 then return end
    local hash = GetPtrHash(player)
    local effect = effects[hash]
    local frame = Game():GetFrameCount()
    if not effect or effect.start ~= frame then
        effect = { start = frame, keys = {}, seen = {} }
        effects[hash] = effect
    end
    for _, key in ipairs(keys) do
        if not effect.seen[key] then
            effect.seen[key] = true
            effect.keys[#effect.keys + 1] = key
        end
    end
end

function Hits.clearEffects()
    effects = {}
end

local function isReflectionPass()
    local room = Game():GetRoom()
    return RenderMode and type(room.GetRenderMode) == "function"
        and room:GetRenderMode() == RenderMode.RENDER_WATER_REFLECT
end

function Hits.onPlayerRender(_, player)
    if not next(effects) or not player then return end
    local hash = GetPtrHash(player)
    local effect = effects[hash]
    if not effect then return end
    local age = Game():GetFrameCount() - effect.start
    if age < 0 or age >= EFFECT_UPDATES then
        effects[hash] = nil
        return
    end
    if isReflectionPass() then return end
    local pop = math.min(1, (age + 1) / POP_UPDATES)
    local alpha = math.min(1, (EFFECT_UPDATES - age) / FADE_UPDATES)
    -- A quick red flash that settles to the icon's own colour.
    local red = math.max(0, 1 - age / POP_UPDATES / 2)
    local scale = ICON_SCALE * (0.7 + 0.3 * pop)
    local base = Isaac.WorldToScreen(player.Position + player.PositionOffset)
    local y = base.Y - HEAD_HEIGHT * player.SpriteScale.Y - RISE * age / EFFECT_UPDATES
    local width = (#effect.keys - 1) * ICON_SPACING
    for i, key in ipairs(effect.keys) do
        local sprite = iconSprite(key)
        if sprite then
            sprite.Scale = Vector(scale, scale)
            sprite.Color = Color(1, 1 - 0.6 * red, 1 - 0.6 * red, alpha, 0.4 * red, 0, 0)
            sprite:RenderLayer(1, Vector(base.X - width / 2 + (i - 1) * ICON_SPACING, y))
        end
    end
end

-- ---------------------------------------------------------------- dispatch
local function dispatch(entity, amount, flags, source, countdown)
    local player = entity and entity:ToPlayer()
    if not player then return end
    local shown = {}
    for _, key in ipairs(Hits.order) do
        local ok, result = pcall(Hits.handlers[key], nil, entity, amount, flags, source, countdown)
        if not ok then
            ConchBlessing.printError("[PlayerHits] " .. key .. " hit handler failed: " .. tostring(result))
        elseif type(result) == "table" then
            for _, shownKey in ipairs(result) do shown[#shown + 1] = shownKey end
        elseif result then
            shown[#shown + 1] = key
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
on(ModCallbacks.MC_PRE_GAME_EXIT, Hits.clearEffects)
on(ModCallbacks.MC_POST_GAME_STARTED, Hits.clearEffects)

Hits._test = {
    -- The keys whose icons are showing above this player, or nil.
    shown = function(player)
        local effect = player and effects[GetPtrHash(player)]
        if not effect or Game():GetFrameCount() - effect.start >= EFFECT_UPDATES then return nil end
        return effect.keys
    end,
    dispatch = dispatch,
}

return Hits
