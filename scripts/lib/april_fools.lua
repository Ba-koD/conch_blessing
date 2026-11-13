local require = ConchBlessingRequire or require -- reloadable loader, see main.lua
-- Cosmetic sheet/crop substitution. The engine still draws the original
-- animation: pedestal, shadow, bob, colour, visibility and grip layers remain
-- native. Never infer a hidden pedestal's visible picture from its SubType.
--
-- Every catalogued layer is in one of two states:
--   original: its own sheet at its own crop (its base);
--   3D:       the catalogued sheet; a turning strip shows base + 32 px per frame.
-- Apply puts a layer in the 3D state, restore puts it back. A strip frame is
-- 32 px wide and never part of a base, so a crop found inside a strip is folded
-- back into its first frame: whatever a reload, a missed restore or an engine
-- reset left behind, the layer is drawn from inside its sheet on the next pass
-- instead of from empty texture (invisible art, user report 2026-11-13).
local Config = require("scripts.conch_blessing_config")
local Catalogue = require("scripts.lib.april_fools_assets")
local M = {}

-- Records of the layers we changed, by who owns the sprite. GetSprite returns
-- a fresh userdata wrapper on every engine call (measured 2026-11-11), so an
-- entity's or a door's record is keyed by the entity / door slot and finds its
-- sprite again from there; only standalone Sprites are their own key.
local standalone = setmetatable({}, { __mode = "k" }) -- sprite -> layers
local owned = {}            -- key -> { ref = EntityPtr | slot = door slot, layers }

local function alive(entry)
    if entry.ref then
        local entity = entry.ref.Ref
        return entity ~= nil and entity:Exists()
    end
    return true
end

local function spriteOf(entry)
    if entry.ref then
        local entity = entry.ref.Ref
        return entity and entity:Exists() and entity:GetSprite() or nil
    end
    local door = Game():GetRoom():GetDoor(entry.slot)
    return door and door:GetSprite() or nil
end
local watched = setmetatable({}, { __mode = "k" })
local enabled = false
local unloading = false
local warned = false
-- After the switch goes off, layers that still show 3D (a record that was
-- lost, an orphan after a reload) are put back as they are drawn, for a while.
local HEAL_UPDATES = 60
local healUntil = -1
-- Room entities known to show no catalogued sheet (see world below).
local plain = {}

local reverse = {}
for original, row in pairs(Catalogue) do
    reverse[row.still:lower()] = original
    if row.spin then reverse[row.spin:lower()] = original end
end

local function normalise(value, sprite)
    local s = tostring(value or ""):gsub("\\", "/"):lower()
    local full = s:match("(gfx/.*)$")
    if not full and sprite and type(sprite.GetFilename) == "function" then
        local file = tostring(sprite:GetFilename()):gsub("\\", "/"):lower()
        local directory = file:match("(gfx/.*/)") or file:match("(gfx/)")
        if directory then full = directory .. s end
    end
    local segments = {}
    for segment in (full or s):gmatch("[^/]+") do
        if segment == ".." then table.remove(segments)
        elseif segment ~= "." then segments[#segments + 1] = segment end
    end
    return table.concat(segments, "/")
end

-- A sheet path is normalised once: every visible layer of every entity asks
-- each update, and a room holds few distinct sheets. A path without its own
-- gfx/ folder depends on the sprite's anm2 folder too, so that is in its key.
local normalised = {}
local function path(value, sprite)
    local raw = tostring(value or "")
    local key = raw
    if not raw:lower():find("gfx[/\\]") and sprite and type(sprite.GetFilename) == "function" then
        key = raw .. "|" .. tostring(sprite:GetFilename())
    end
    local hit = normalised[key]
    if not hit then
        hit = normalise(raw, sprite)
        normalised[key] = hit
    end
    return hit
end

-- Sheet swaps made by Apply since load, by sheet: a sprite swapped again every
-- frame would reload its texture every frame (conch_test april_fools counts them).
M.swaps = {}

local function equal(a, b)
    return a and b and a.X == b.X and a.Y == b.Y
end

local function fold(c)
    return Vector(c.X % 32, c.Y)
end

-- Whether a crop is one of our strip frames over `base` (not the base itself).
local function onStrip(c, base, frames)
    local dx = c.X - base.X
    return c.Y == base.Y and dx >= 32 and dx % 32 == 0 and dx <= 32 * ((frames or 32) - 1)
end

local function turns(row, layer)
    return row.spin ~= nil and type(layer.SetCropOffset) == "function" and type(layer.GetCropOffset) == "function"
end

-- Put our crop back to the layer's base, if the crop is still ours.
local function settleCrop(layer, saved)
    if not saved.base then return false end
    local c = layer:GetCropOffset()
    if equal(c, saved.last) or onStrip(c, saved.base, saved.frames) then
        layer:SetCropOffset(Vector(saved.base.X, saved.base.Y))
        return true
    end
    return false
end

local function restore(sprite, layers)
    local dirty, crops = false, {}
    for id, saved in pairs(layers) do
        local layer = sprite:GetLayer(id)
        if layer then
            -- Do not overwrite a reroll, a blind image, or another mod's new art.
            if path(layer:GetSpritesheetPath(), sprite) == saved.target then
                sprite:ReplaceSpritesheet(id, saved.original)
                dirty = true
            end
            if saved.base then
                local c = layer:GetCropOffset()
                if equal(c, saved.last) or onStrip(c, saved.base, saved.frames) then crops[id] = saved.base end
            end
        end
    end
    if dirty then sprite:LoadGraphics() end
    -- A graphics reload may rebuild layer state, so crops go on afterwards.
    for id, crop in pairs(crops) do sprite:GetLayer(id):SetCropOffset(Vector(crop.X, crop.Y)) end
end

function M.RestoreAll()
    for sprite, layers in pairs(standalone) do
        local ok, err = pcall(restore, sprite, layers)
        if not ok then ConchBlessing.printDebug("[AprilFools] expired sprite: %s", tostring(err)) end
    end
    for _, entry in pairs(owned) do
        local sprite = spriteOf(entry)
        if sprite then
            local ok, err = pcall(restore, sprite, entry.layers)
            if not ok then ConchBlessing.printDebug("[AprilFools] expired sprite: %s", tostring(err)) end
        end
    end
    standalone = setmetatable({}, { __mode = "k" })
    owned = {}
end

function M.Refresh()
    local nextEnabled = not unloading and Config.IsAprilFools3D()
    if enabled and not nextEnabled then
        M.RestoreAll()
        healUntil = Game():GetFrameCount() + HEAL_UPDATES
    end
    if nextEnabled and not enabled then plain = {} end
    enabled = nextEnabled
    return enabled
end

-- Persistent standalone sprites (e.g. EID icons) may be created while off.
-- Watch keeps them eligible for an immediate setting change without reloading.
function M.Watch(sprite)
    if sprite then watched[sprite] = true; M.Apply(sprite) end
end

local function canInspect(sprite)
    if type(sprite.GetAllLayers) == "function" and type(sprite.GetLayer) == "function" then return true end
    if not warned then
        warned = true
        ConchBlessing.printError("April Fools 3D needs REPENTOGON sprite-layer inspection; original art retained.")
    end
    return false
end

local function trace(key, id, current, target)
    if not M.trace then return end
    M.trace[#M.trace + 1] = string.format("g%d r%d %s L%d %s -> %s", Game():GetFrameCount(),
        Isaac.GetFrameCount(), key and tostring(key) or "s", id,
        current:match("[^/]+$") or current, target:match("[^/]+$") or target)
end

-- Off, shortly after the switch: a layer still drawn from one of our 3D
-- sheets goes back to its original sheet, its crop into its first frame.
local function heal(sprite)
    local dirty, crops = false, {}
    for _, layer in ipairs(sprite:GetAllLayers()) do
        if type(layer.GetSpritesheetPath) == "function" and type(layer.GetLayerID) == "function" then
            local current = path(layer:GetSpritesheetPath(), sprite)
            local original = reverse[current]
            if original and original ~= current then
                local id = layer:GetLayerID()
                sprite:ReplaceSpritesheet(id, original)
                dirty = true
                if Catalogue[original].spin and type(layer.GetCropOffset) == "function" then
                    crops[id] = fold(layer:GetCropOffset())
                end
            end
        end
    end
    if dirty then sprite:LoadGraphics() end
    for id, crop in pairs(crops) do sprite:GetLayer(id):SetCropOffset(crop) end
end

-- The 3D state for every catalogued layer of `sprite`, whose records live in
-- `layers`. Returns whether any layer is ours.
local function applyLayers(sprite, layers, key)
    local dirty = false
    for _, layer in ipairs(sprite:GetAllLayers()) do
        if type(layer.GetSpritesheetPath) == "function" and type(layer.GetLayerID) == "function" then
            local id = layer:GetLayerID()
            local actual = layer:GetSpritesheetPath()
            local current = path(actual, sprite)
            local saved = layers[id]
            -- Something else now draws on this layer (a native turn, a reroll,
            -- a module's own picture): our crop and our record go.
            if saved and current ~= saved.target then
                settleCrop(layer, saved)
                layers[id], saved = nil, nil
            end
            local original = reverse[current] or current
            local row = Catalogue[original]
            if row then
                local strip = turns(row, layer)
                local target = strip and row.spin or row.still
                if not saved then
                    -- ReplaceSpritesheet uses resource-root paths, unlike an
                    -- ANM2's default sheet, which can be relative to its file.
                    local restorePath = actual
                    if reverse[current] or not tostring(actual):lower():find("gfx[/\\]") then
                        restorePath = original
                    end
                    saved = { original = restorePath, target = path(target) }
                    if strip then saved.base, saved.frames = fold(layer:GetCropOffset()), row.frames end
                    layers[id] = saved
                end
                if current ~= saved.target then
                    sprite:ReplaceSpritesheet(id, target)
                    M.swaps[target] = (M.swaps[target] or 0) + 1
                    trace(key, id, current, target)
                    dirty = true
                end
                if strip then
                    -- A native crop change (another animation row) is the new base.
                    local c = layer:GetCropOffset()
                    if saved.last and not equal(c, saved.last) then saved.base = fold(c) end
                    -- The game counter stops while paused. No gameplay RNG,
                    -- Render() count, entity Update(), or animation reset.
                    local frame = math.floor(Game():GetFrameCount() / row.delay) % row.frames
                    saved.last = Vector(saved.base.X + 32 * frame, saved.base.Y)
                    layer:SetCropOffset(saved.last)
                end
            end
        end
    end
    if dirty then
        sprite:LoadGraphics()
        -- Some providers rebuild layer state on graphics reload.
        for id, saved in pairs(layers) do
            if saved.last then sprite:GetLayer(id):SetCropOffset(saved.last) end
        end
    end
    return next(layers) ~= nil
end

-- `key` and `make` name a stable owner for a sprite the engine hands out
-- afresh on every call (an entity, a door); nil for a standalone Sprite.
local function applyTo(sprite, key, make)
    if not sprite then return end
    if not enabled then
        if Game():GetFrameCount() <= healUntil and canInspect(sprite) then heal(sprite) end
        return
    end
    if not canInspect(sprite) then return end
    if key then
        local entry = owned[key]
        -- a new owner at a reused address starts clean
        if not (entry and alive(entry)) then entry = make() end
        if applyLayers(sprite, entry.layers, key) then owned[key] = entry else owned[key] = nil end
    else
        local layers = standalone[sprite] or {}
        if applyLayers(sprite, layers, nil) then standalone[sprite] = layers else standalone[sprite] = nil end
    end
end

-- A standalone Sprite, or an entity's sprite with that entity as `owner`.
function M.Apply(sprite, owner)
    if not owner then return applyTo(sprite) end
    return applyTo(sprite, GetPtrHash(owner), function() return { ref = EntityPtr(owner), layers = {} } end)
end

local function applyDoor(slot)
    local door = Game():GetRoom():GetDoor(slot)
    if not door then return end
    applyTo(door:GetSprite(), "door" .. slot, function() return { slot = slot, layers = {} } end)
end

-- The calendar is read once every two seconds (it allocates a date table and
-- runs through pcall, about 0.2 ms an update when it ran every update, mostly
-- while the feature is off); the MCM switch, game start and unload refresh at
-- once, so only the change of date itself waits up to two seconds.
local REFRESH_EVERY, nextRefresh = 60, -1

-- Most room entities (vanilla enemies, tears, effects) never show a catalogued
-- sheet. An entity found without one is skipped while its type, variant and
-- subtype stay the same, and looked at again every second in case a sheet was
-- swapped in some other way. Pickups are left to their own render callback,
-- which applies them right before every draw.
local RECHECK = 30

local function world()
    local frame = Game():GetFrameCount()
    if frame >= nextRefresh or frame < nextRefresh - REFRESH_EVERY then
        nextRefresh = frame + REFRESH_EVERY
        M.Refresh()
    end
    if not enabled and frame > healUntil then return end
    for sprite in pairs(watched) do applyTo(sprite) end
    local pickupsRender = ModCallbacks.MC_PRE_PICKUP_RENDER ~= nil
    for _, entity in ipairs(Isaac.GetRoomEntities()) do
        if not (pickupsRender and entity.Type == EntityType.ENTITY_PICKUP) then
            local key = GetPtrHash(entity)
            local seen = enabled and plain[key]
            if not (seen and seen.until_ > frame and seen.type == entity.Type
                and seen.variant == entity.Variant and seen.subtype == entity.SubType) then
                M.Apply(entity:GetSprite(), entity)
                if not enabled then
                    plain[key] = nil
                elseif owned[key] then
                    plain[key] = nil
                else
                    plain[key] = { type = entity.Type, variant = entity.Variant,
                        subtype = entity.SubType, until_ = frame + RECHECK }
                end
            end
        end
    end
    -- Native doors are not in GetRoomEntities; StageAPI doors are effects and
    -- are already covered above. Only catalogued, mod-owned sheets match.
    for slot = 0, 7 do applyDoor(slot) end
end

ConchBlessing.AprilFools = M
-- Read-only views for conch_test april_fools.
M._test = { path = path, reverse = reverse }
ConchBlessing:AddCallback(ModCallbacks.MC_POST_UPDATE, world)
-- A rotating pedestal can replace its visible sheet after the update pass.
-- Observe that exact picture again before drawing so a stale crop can never
-- carry across a morph into a question mark or another mod's sprite.
if ModCallbacks.MC_PRE_PICKUP_RENDER then
    ConchBlessing:AddCallback(ModCallbacks.MC_PRE_PICKUP_RENDER, function(_, pickup)
        M.Apply(pickup:GetSprite(), pickup)
    end)
end
if ModCallbacks.MC_PRE_CHANGE_ROOM then
    ConchBlessing:AddCallback(ModCallbacks.MC_PRE_CHANGE_ROOM, function() M.RestoreAll() end)
end
if ModCallbacks.MC_POST_NEW_ROOM then
    ConchBlessing:AddCallback(ModCallbacks.MC_POST_NEW_ROOM, function() plain = {} end)
end
ConchBlessing:AddCallback(ModCallbacks.MC_POST_ENTITY_REMOVE, function(_, entity)
    local key = GetPtrHash(entity)
    owned[key], plain[key] = nil, nil
end)
-- The heal window counts game frames, which start again from 0 in the next
-- run: a window left open would heal every drawn sprite for that long.
ConchBlessing:AddCallback(ModCallbacks.MC_PRE_GAME_EXIT, function() M.RestoreAll(); enabled, healUntil = false, -1 end)
ConchBlessing:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, function() M.RestoreAll(); healUntil = -1; M.Refresh() end)
if ModCallbacks.MC_PRE_MOD_UNLOAD then
    ConchBlessing:AddCallback(ModCallbacks.MC_PRE_MOD_UNLOAD, function(_, mod)
        if mod == ConchBlessing or mod == ConchBlessing.originalMod then
            unloading = true
            M.RestoreAll()
            enabled = false
        end
    end)
end
M.Refresh()
return M
