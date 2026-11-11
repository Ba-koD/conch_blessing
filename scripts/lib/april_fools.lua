local require = ConchBlessingRequire or require -- reloadable loader, see main.lua
-- Cosmetic sheet/crop substitution. The engine still draws the original
-- animation: pedestal, shadow, bob, colour, visibility and grip layers remain
-- native. Never infer a hidden pedestal's visible picture from its SubType.
local Config = require("scripts.conch_blessing_config")
local Catalogue = require("scripts.lib.april_fools_assets")
local M = {}
-- GetSprite returns a fresh userdata wrapper on every engine call. Only
-- standalone Sprites have a stable Lua identity; live entities own their
-- layer baseline through EntityPtr/GetPtrHash instead (measured 2026-11-11).
local records = setmetatable({}, { __mode = "k" })
local entityRecords = {}
local watched = setmetatable({}, { __mode = "k" })
local enabled = false
local unloading = false
local warned = false
local reverse = {}
for original, row in pairs(Catalogue) do
    reverse[row.still:lower()] = original
    if row.spin then reverse[row.spin:lower()] = original end
end

local function path(value, sprite)
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

local function equal(a, b)
    return a and b and a.X == b.X and a.Y == b.Y
end

local function restore(sprite, rec)
    local dirty = false
    local crops = {}
    for id, saved in pairs(rec) do
        local layer = sprite:GetLayer(id)
        if layer then
            -- Do not overwrite a reroll, a blind image, or another mod's new art.
            if path(layer:GetSpritesheetPath(), sprite) == saved.applied then
                sprite:ReplaceSpritesheet(id, saved.original)
                dirty = true
            end
            if saved.crop and equal(layer:GetCropOffset(), saved.lastCrop) then
                crops[id] = Vector(saved.crop.X, saved.crop.Y)
            end
        end
    end
    if dirty then sprite:LoadGraphics() end
    for id, crop in pairs(crops) do sprite:GetLayer(id):SetCropOffset(crop) end
end

function M.RestoreAll()
    for sprite, rec in pairs(records) do
        local ok, err = pcall(restore, sprite, rec)
        if not ok then ConchBlessing.printDebug("[AprilFools] expired sprite: " .. tostring(err)) end
    end
    for _, entry in pairs(entityRecords) do
        local entity = entry.owner.Ref
        if entity and entity:Exists() then
            local ok, err = pcall(restore, entity:GetSprite(), entry.layers)
            if not ok then ConchBlessing.printDebug("[AprilFools] expired sprite: " .. tostring(err)) end
        end
    end
    records = setmetatable({}, { __mode = "k" })
    entityRecords = {}
end

function M.Refresh()
    local nextEnabled = not unloading and Config.IsAprilFools3D()
    if enabled and not nextEnabled then M.RestoreAll() end
    enabled = nextEnabled
    return enabled
end

-- Persistent standalone sprites (e.g. EID icons) may be created while off.
-- Watch keeps them eligible for an immediate setting change without reloading.
function M.Watch(sprite)
    if sprite then watched[sprite] = true; M.Apply(sprite) end
end

function M.Apply(sprite, owner)
    if not sprite then return end
    if not enabled then return end
    if type(sprite.GetAllLayers) ~= "function" or type(sprite.GetLayer) ~= "function" then
        if not warned then
            warned = true
            ConchBlessing.printError("April Fools 3D needs REPENTOGON sprite-layer inspection; original art retained.")
        end
        return
    end
    local ownerKey = owner and GetPtrHash(owner)
    local owned = ownerKey and entityRecords[ownerKey]
    if owned and (not owned.owner.Ref or not owned.owner.Ref:Exists()) then
        entityRecords[ownerKey], owned = nil, nil
    end
    local rec = owned and owned.layers or records[sprite] or {}
    if ownerKey then records[sprite] = nil end
    local dirty = false
    for _, layer in ipairs(sprite:GetAllLayers()) do
        if type(layer.GetSpritesheetPath) == "function" and type(layer.GetLayerID) == "function" then
            local id = layer:GetLayerID()
            local actual = layer:GetSpritesheetPath()
            local current = path(actual, sprite)
            local saved = rec[id]
            -- Renewed native animation / external sheet replacement cancels our
            -- old crop before considering the new visible picture.
            if saved and current ~= saved.applied then
                if saved.crop and equal(layer:GetCropOffset(), saved.lastCrop) then
                    layer:SetCropOffset(Vector(saved.crop.X, saved.crop.Y))
                end
                rec[id], saved = nil, nil
            end
            local original = reverse[current] or current
            local row = Catalogue[original]
            if row then
                local canSpin = row.spin and type(layer.SetCropOffset) == "function"
                    and type(layer.GetCropOffset) == "function"
                local target = canSpin and row.spin or row.still
                if not saved then
                    -- ReplaceSpritesheet uses resource-root paths, unlike an
                    -- ANM2's default sheet, which can be relative to its file.
                    local restorePath = actual
                    if reverse[current] or not tostring(actual):lower():find("gfx[/\\]") then
                        restorePath = original
                    end
                    saved = { original = restorePath, applied = path(target) }
                    if canSpin then
                        local c = layer:GetCropOffset()
                        saved.crop = Vector(c.X, c.Y)
                        if current == path(row.spin) then
                            -- Recover our own orphaned strip after a reload:
                            -- its frame phase is not a new native crop baseline.
                            saved.crop.X = saved.crop.X % 32
                        end
                    end
                    rec[id] = saved
                end
                if current ~= path(target) then
                    sprite:ReplaceSpritesheet(id, target)
                    dirty = true
                end
                if canSpin then
                    local currentCrop = layer:GetCropOffset()
                    if saved.lastCrop and not equal(currentCrop, saved.lastCrop) then
                        saved.crop = Vector(currentCrop.X, currentCrop.Y)
                    end
                    -- The game counter stops while paused. No gameplay RNG,
                    -- Render() count, entity Update(), or animation reset.
                    local frame = math.floor(Game():GetFrameCount() / row.delay) % row.frames
                    saved.lastCrop = Vector(saved.crop.X + 32 * frame, saved.crop.Y)
                    layer:SetCropOffset(saved.lastCrop)
                end
            end
        end
    end
    if next(rec) then
        if ownerKey then
            entityRecords[ownerKey] = owned or { owner = EntityPtr(owner), layers = rec }
        else
            records[sprite] = rec
        end
    else
        if ownerKey then entityRecords[ownerKey] = nil
        else records[sprite] = nil end
    end
    if dirty then
        sprite:LoadGraphics()
        -- Some providers rebuild layer state on graphics reload.
        for id, saved in pairs(rec) do
            if saved.lastCrop then sprite:GetLayer(id):SetCropOffset(saved.lastCrop) end
        end
    end
end

local function world()
    if not M.Refresh() then return end
    for sprite in pairs(watched) do M.Apply(sprite) end
    for _, entity in ipairs(Isaac.GetRoomEntities()) do
        M.Apply(entity:GetSprite(), entity)
    end
    -- Native doors are not in GetRoomEntities; StageAPI doors are effects and
    -- are already covered above. Only catalogued, mod-owned sheets match.
    local room = Game():GetRoom()
    for slot = 0, 7 do
        local door = room:GetDoor(slot)
        if door then M.Apply(door:GetSprite()) end
    end
end

ConchBlessing.AprilFools = M
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
ConchBlessing:AddCallback(ModCallbacks.MC_POST_ENTITY_REMOVE, function(_, entity)
    entityRecords[GetPtrHash(entity)] = nil
end)
ConchBlessing:AddCallback(ModCallbacks.MC_PRE_GAME_EXIT, function() M.RestoreAll(); enabled = false end)
ConchBlessing:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, function() M.RestoreAll(); M.Refresh() end)
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
