local require = ConchBlessingRequire or require -- reloadable loader, see main.lua
-- Conch's Blessing - upgradeable pickup previews and the Magic Conch HUD pulse
--
-- An upgradeable pickup shows what each Magic Conch answer would turn it into
-- (scripts/lib/upgrade_branch_preview.lua) while a player stands near it, and
-- hops every few seconds while nobody is. Both are cosmetic: the tree is drawn
-- with standalone sprites, and the hop only borrows the item layer's position
-- and size, restored before an upgrade, on every boundary and on unload.

local UpgradeHighlight = ConchBlessing.UpgradeHighlight or {}
ConchBlessing.UpgradeHighlight = UpgradeHighlight
local Preview = require("scripts.lib.upgrade_branch_preview")
local Config = require("scripts.conch_blessing_config")

local FLAG_ORDER = { "positive", "neutral", "negative" }
local ROOM_SCAN_INTERVAL = 15
local HUD_PULSE_PERIOD = 34
local HUD_PULSE_DECAY_FRAMES = 30
local HUD_PULSE_BASE_BRIGHTNESS = 1.0
local HUD_PULSE_PEAK_BRIGHTNESS = 2.15
local HUD_PULSE_BASE_ALPHA = 0.0
local HUD_PULSE_PEAK_ALPHA = 0.72
-- A tree opens when a player comes within the MCM preview range and closes a
-- quarter further out, so standing at the edge does not flicker
-- (Config.GetPreviewRanges, read each update so a changed setting applies at once).
local CLOSE_RATE = 1.5
local EVENT_LIMIT = 40

UpgradeHighlight._previews = UpgradeHighlight._previews or {}
UpgradeHighlight._previewClock = UpgradeHighlight._previewClock or 0
UpgradeHighlight._previewEvents = UpgradeHighlight._previewEvents or {}

local function tableHasEntries(t)
    return type(t) == "table" and next(t) ~= nil
end

local function getFrame()
    local ok, frame = pcall(function()
        return Game():GetFrameCount()
    end)
    if ok and type(frame) == "number" then
        return frame
    end
    return Isaac.GetFrameCount()
end

local function getPickupHash(pickup)
    if type(GetPtrHash) == "function" then
        return tostring(GetPtrHash(pickup))
    end
    return tostring(pickup.InitSeed) .. ":" .. tostring(pickup.Variant)
end

local function isUpgradeablePickupVariant(variant)
    return variant == PickupVariant.PICKUP_COLLECTIBLE or variant == PickupVariant.PICKUP_TRINKET
end

local function normalizePickup(entity)
    if not entity or not entity.Exists or not entity:Exists() then
        return nil
    end
    if entity.Type ~= EntityType.ENTITY_PICKUP or not isUpgradeablePickupVariant(entity.Variant) then
        return nil
    end
    return entity:ToPickup()
end

local function lerp(a, b, t)
    return (a or 0) + (((b or 0) - (a or 0)) * t)
end

local function getDecayPulse(frame, period, decayFrames)
    local cycleFrame = frame % period
    if cycleFrame >= decayFrames then
        return 0
    end

    local decayProgress = cycleFrame / decayFrames
    return 0.5 + 0.5 * math.cos(decayProgress * math.pi)
end

-- The rotation that starts at the smallest sequence, so a rotating pedestal
-- keeps one identity (and one tree layout) whichever choice it shows.
local function getCanonicalCycle(itemIds)
    local bestOffset = 1
    for candidateOffset = 2, #itemIds do
        for step = 0, #itemIds - 1 do
            local candidate = itemIds[((candidateOffset + step - 1) % #itemIds) + 1]
            local best = itemIds[((bestOffset + step - 1) % #itemIds) + 1]
            if candidate < best then
                bestOffset = candidateOffset
                break
            elseif candidate > best then
                break
            end
        end
    end

    local ordered, parts = {}, {}
    for step = 0, #itemIds - 1 do
        ordered[#ordered + 1] = itemIds[((bestOffset + step - 1) % #itemIds) + 1]
        parts[#parts + 1] = tostring(ordered[#ordered])
    end
    return "CYCLE:" .. table.concat(parts, ","), ordered
end

local function getPickupOriginInfo(pickup)
    if not pickup or not isUpgradeablePickupVariant(pickup.Variant) then
        return nil
    end

    local rawId = pickup.SubType
    if type(rawId) ~= "number" or rawId <= 0 then
        return nil
    end

    -- The logical circle is the shown SubType followed by REPENTOGON's queued
    -- tail. Without that API a turning pedestal is read as its shown choice.
    if pickup.Variant == PickupVariant.PICKUP_COLLECTIBLE
        and type(pickup.GetCollectibleCycle) == "function" then
        local ok, queue = pcall(function()
            return pickup:GetCollectibleCycle()
        end)
        if ok and type(queue) == "table" and #queue > 0 then
            local itemIds = { rawId }
            for _, itemId in ipairs(queue) do
                if type(itemId) ~= "number" or itemId <= 0 then
                    itemIds = nil
                    break
                end
                itemIds[#itemIds + 1] = itemId
            end
            if itemIds then
                local identity, ordered = getCanonicalCycle(itemIds)
                local originKeys = {}
                for _, itemId in ipairs(ordered) do
                    originKeys[#originKeys + 1] = "C:" .. tostring(itemId)
                end
                return { identity = identity, originKeys = originKeys, cycle = true }
            end
        end
    end

    local isTrinket = pickup.Variant == PickupVariant.PICKUP_TRINKET
    local baseId = (isTrinket and rawId >= 32768) and (rawId - 32768) or rawId
    local prefix = isTrinket and "T:" or "C:"
    local originKey = prefix .. tostring(baseId)
    return {
        identity = originKey,
        originKeys = { originKey },
        cycle = false,
    }
end

local function getPickupUpgradeInfo(pickup)
    local maps = ConchBlessing.ItemMaps
    if not tableHasEntries(maps) then
        return nil
    end

    local originInfo = getPickupOriginInfo(pickup)
    if not originInfo then
        return nil
    end

    local seen = {}
    for _, originKey in ipairs(originInfo.originKeys) do
        local mappings = maps[originKey]
        if tableHasEntries(mappings) then
            for flag in pairs(mappings) do
                seen[flag] = true
            end
        end
    end

    local flags = {}
    for _, flag in ipairs(FLAG_ORDER) do
        if seen[flag] then
            table.insert(flags, flag)
            seen[flag] = nil
        end
    end
    for flag in pairs(seen) do
        table.insert(flags, flag)
    end

    if #flags == 0 then
        return nil
    end

    return {
        originKey = originInfo.identity,
        originKeys = originInfo.originKeys,
        cycle = originInfo.cycle,
        flags = flags,
    }
end
UpgradeHighlight.getPickupUpgradeInfo = getPickupUpgradeInfo

local function isMorphing(pickup)
    local upgrade = ConchBlessing.upgrade
    if upgrade and upgrade.isAnimatingPickup and upgrade.isAnimatingPickup(pickup) then return true end
    local template = ConchBlessing.template
    return template and template.isAnimatingPickup and template.isAnimatingPickup(pickup) or false
end

local function isViewerPickup(pickup)
    local viewer = ConchBlessing.morphViewer
    return viewer ~= nil and type(viewer.ownsPickup) == "function" and viewer.ownsPickup(pickup) == true
end

-- A question-mark pedestal must not reveal its item through its results.
-- REPENTOGON's IsBlind covers the alternate-path choice but not the curse.
-- Without it that alternate-path choice cannot be told apart, so treasure
-- rooms on those floors show nothing rather than risk revealing it.
local function isHiddenPickup(pickup)
    if pickup.Variant ~= PickupVariant.PICKUP_COLLECTIBLE then
        return false
    end
    local canTellBlind = type(pickup.IsBlind) == "function"
    if canTellBlind then
        local ok, blind = pcall(pickup.IsBlind, pickup)
        if not ok or blind then return true end
    end
    local game = Game()
    local level = game:GetLevel()
    if LevelCurse and LevelCurse.CURSE_OF_BLIND
        and (level:GetCurses() & LevelCurse.CURSE_OF_BLIND) ~= 0 and not pickup.Touched then
        return true
    end
    if not canTellBlind then
        local stageType = level:GetStageType()
        return game:GetRoom():GetType() == RoomType.ROOM_TREASURE
            and (stageType == StageType.STAGETYPE_REPENTANCE or stageType == StageType.STAGETYPE_REPENTANCE_B)
    end
    return false
end

local function debugOn()
    return ConchBlessing.Config and ConchBlessing.Config.debugMode and type(ConchBlessing.printDebug) == "function"
end

-- Runtime evidence only (never saved): conch_test evolution reads it, and
-- debug mode mirrors it to the log.
local function record(event, rec, detail)
    local events = UpgradeHighlight._previewEvents
    events[#events + 1] = { event = event, hash = rec.hash, identity = rec.identity, detail = detail,
        frame = getFrame() }
    if #events > EVENT_LIMIT then table.remove(events, 1) end
    if debugOn() then
        ConchBlessing.printDebug(string.format("[EvolutionPreview] %s %s%s", event, tostring(rec.identity),
            detail and (" " .. tostring(detail)) or ""))
    end
end

-- One group per evolvable origin, its results in answer order. A rotating
-- pedestal lists each evolvable choice once, in its canonical circle order.
local function previewGroups(info)
    local maps = ConchBlessing.ItemMaps
    local function results(originKey)
        local list = {}
        for _, flag in ipairs(FLAG_ORDER) do
            local mapping = maps[originKey] and maps[originKey][flag]
            if mapping then
                list[#list + 1] = { flag = flag, id = mapping.upgradeId,
                    trinket = mapping.itemData ~= nil and mapping.itemData.type == "trinket" }
            end
        end
        return list
    end

    if not info.cycle then
        return { { results = results(info.originKeys[1]) } }, false
    end
    local groups, seen = {}, {}
    for _, originKey in ipairs(info.originKeys) do
        if not seen[originKey] then
            seen[originKey] = true
            local list = results(originKey)
            if #list > 0 then
                groups[#groups + 1] = { source = { id = tonumber(originKey:sub(3)) }, results = list }
            end
        end
    end
    return groups, true
end

local function livePreviewPickup(rec)
    local entity = rec.ptr and rec.ptr.Ref
    if entity and entity:Exists() and getPickupHash(entity) == rec.hash then
        return entity:ToPickup()
    end
end

-- The hop borrows only the item layer (a pedestal's "head", a trinket's
-- "body"), so the pedestal, shadow and price stay where they are.
local function hopLayer(pickup)
    local sprite = pickup and pickup:GetSprite()
    if not sprite or type(sprite.GetLayer) ~= "function" then return nil end
    local name = pickup.Variant == PickupVariant.PICKUP_COLLECTIBLE and "head" or "body"
    local ok, layer = pcall(sprite.GetLayer, sprite, name)
    if ok and layer and type(layer.GetPos) == "function" and type(layer.SetPos) == "function"
        and type(layer.GetSize) == "function" and type(layer.SetSize) == "function" then
        return layer
    end
end

local function restoreHop(rec, pickup)
    local saved = rec.hop
    if not saved then return end
    rec.hop = nil
    local layer = pickup and hopLayer(pickup)
    if layer then
        layer:SetPos(Vector(saved.pos.X, saved.pos.Y))
        layer:SetSize(Vector(saved.size.X, saved.size.Y))
    end
end

local function applyHop(rec, pickup, pose)
    local layer = hopLayer(pickup)
    if not layer then
        rec.hopUnavailable = true
        return
    end
    if not rec.hop then
        -- Copy by value: a getter may lend the layer's own storage.
        local pos, size = layer:GetPos(), layer:GetSize()
        rec.hop = { pos = Vector(pos.X, pos.Y), size = Vector(size.X, size.Y) }
        rec.hops = rec.hops + 1
    end
    local saved = rec.hop
    layer:SetPos(Vector(saved.pos.X, saved.pos.Y + pose.dy))
    layer:SetSize(Vector(saved.size.X * pose.sx, saved.size.Y * pose.sy))
end

local function endPreview(hash, rec, reason, pickup)
    restoreHop(rec, pickup or livePreviewPickup(rec))
    UpgradeHighlight._previews[hash] = nil
    record("END", rec, reason)
end

local function trackPreview(pickup, info)
    if not pickup or not info then return end
    local hash = getPickupHash(pickup)
    local previews = UpgradeHighlight._previews
    local rec = previews[hash]
    if rec and rec.identity == info.originKey then
        if not livePreviewPickup(rec) then
            -- A native Morph (a rotating pedestal turning) renews the entity
            -- under the same address. Follow it and put back a borrowed hop.
            rec.ptr = EntityPtr(pickup)
            restoreHop(rec, pickup)
        end
        return
    end
    if isMorphing(pickup) or isViewerPickup(pickup) or isHiddenPickup(pickup) then return end
    if rec then endPreview(hash, rec, "changed") end

    local groups, tree = previewGroups(info)
    if #groups == 0 then return end
    local ok, layout = pcall(Preview.layout, groups, tree)
    if not ok then
        ConchBlessing.printError("[EvolutionPreview] layout failed for " .. tostring(info.originKey) .. ": " .. tostring(layout))
        return
    end
    -- Each pickup keeps its own hop beat (a cosmetic offset from its seed),
    -- so a room of eligible items does not jump in lockstep.
    rec = { ptr = EntityPtr(pickup), hash = hash, identity = info.originKey, groups = groups,
        layout = layout, t = 0, open = false, opens = 0, hops = 0, draws = 0, sparks = 0, pops = 0,
        phase = math.floor(tonumber(pickup.InitSeed) or 0) % Preview.HOP_PERIOD }
    previews[hash] = rec
    record("TRACK", rec, tostring(#groups) .. (tree and " choices" or " group"))
end

local function nearestPlayerDistance(position)
    local best = math.huge
    local game = Game()
    for i = 0, game:GetNumPlayers() - 1 do
        local player = Isaac.GetPlayer(i)
        local pos = player and player.Position
        if pos then
            local dx, dy = pos.X - position.X, pos.Y - position.Y
            best = math.min(best, math.sqrt(dx * dx + dy * dy))
        end
    end
    return best
end

local function stepPreview(rec, pickup, clock)
    local distance = nearestPlayerDistance(pickup.Position)
    local openRange, closeRange = Config.GetPreviewRanges()
    if rec.open and distance > closeRange then
        rec.open = false
        record("CLOSE", rec)
    elseif not rec.open and distance <= openRange then
        rec.open = true
        rec.opens = rec.opens + 1
        record("OPEN", rec)
    end
    if rec.open then
        rec.t = math.min(rec.layout.openEnd, rec.t + 1)
    else
        rec.t = math.max(0, rec.t - CLOSE_RATE)
    end

    -- Out of range the item keeps hopping in place, with no limit, until a
    -- player comes near. A hop starts only while the tree is fully closed; one
    -- already in the air lands before the tree's first lines have grown.
    local phase = (clock + rec.phase) % Preview.HOP_PERIOD
    if phase == 0 then rec.hopping = not rec.open and rec.t == 0 and not rec.hopUnavailable end
    local pose = rec.hopping and Preview.hop(phase)
    if pose then
        applyHop(rec, pickup, pose)
    else
        rec.hopping = false
        restoreHop(rec, pickup)
    end
end

local function updatePreviews()
    local previews = UpgradeHighlight._previews
    if not tableHasEntries(previews) then return end
    UpgradeHighlight._previewClock = UpgradeHighlight._previewClock + 1
    local clock = UpgradeHighlight._previewClock
    local replaced = {}
    -- Only here, after every entity has updated, is a pickup judged changed: a
    -- rotating pedestal's native turn passes through inconsistent cycle states
    -- inside its own init callback (measured 2026-10-23).
    for hash, rec in pairs(previews) do
        local pickup = livePreviewPickup(rec)
        -- An expired reference waits for its pickup to be seen again; it
        -- neither draws nor writes until then.
        if pickup then
            local reason, info
            if isMorphing(pickup) then
                reason = "upgrade"
            else
                info = getPickupUpgradeInfo(pickup)
                if not info or info.originKey ~= rec.identity then
                    reason = "changed"
                elseif isHiddenPickup(pickup) then
                    reason = "hidden"
                end
            end
            if reason then
                endPreview(hash, rec, reason, pickup)
                if reason == "changed" and info then replaced[#replaced + 1] = { pickup, info } end
            else
                stepPreview(rec, pickup, clock)
            end
        end
    end
    for _, entry in ipairs(replaced) do trackPreview(entry[1], entry[2]) end
end

local function clearPreviews(reason)
    for hash, rec in pairs(UpgradeHighlight._previews) do
        endPreview(hash, rec, reason)
    end
    UpgradeHighlight._previews = {}
    UpgradeHighlight._previewClock = 0
end

--- Ends this pickup's preview and puts back its item layer before an upgrade
--- (or a bench) reads the pickup's own presentation.
function UpgradeHighlight.StopForPickup(pickup)
    if not pickup then
        return
    end
    local hash = getPickupHash(pickup)
    local rec = UpgradeHighlight._previews[hash]
    if rec then endPreview(hash, rec, "stopped", pickup) end
end

--- Read-only evidence for conch_test evolution.
function UpgradeHighlight.previewFor(pickup)
    return pickup and UpgradeHighlight._previews[getPickupHash(pickup)] or nil
end
function UpgradeHighlight.previewEvents()
    return UpgradeHighlight._previewEvents
end
function UpgradeHighlight.ranges() return Config.GetPreviewRanges() end

function UpgradeHighlight.ScanRoom(frame)
    frame = frame or getFrame()

    if not tableHasEntries(ConchBlessing.ItemMaps) then
        UpgradeHighlight._roomUpgradeableCount = 0
        UpgradeHighlight._roomHasUpgradeable = false
        UpgradeHighlight._lastScanFrame = frame
        return 0
    end

    local count = 0
    for _, entity in ipairs(Isaac.GetRoomEntities()) do
        local pickup = normalizePickup(entity)
        local info = pickup and getPickupUpgradeInfo(pickup) or nil
        if pickup and info then
            count = count + 1
            trackPreview(pickup, info)
        end
    end

    UpgradeHighlight._roomUpgradeableCount = count
    UpgradeHighlight._roomHasUpgradeable = count > 0
    UpgradeHighlight._lastScanFrame = frame
    return count
end

local function loadHudSprite()
    local magicConch = rawget(_G, "MagicConch")
    local deleteMode = magicConch
        and magicConch.Config
        and magicConch.Config.deleteMode == true

    if UpgradeHighlight._hudSpriteLoaded and UpgradeHighlight._hudLastDeleteMode == deleteMode then
        return UpgradeHighlight._hudSprite
    end

    local sprite = UpgradeHighlight._hudSprite or Sprite()
    local texture = deleteMode and "gfx/MagicConchDel.png" or "gfx/MagicConch.png"
    local ok = pcall(function()
        sprite:Load("gfx/005.100_collectible.anm2", true)
        sprite:ReplaceSpritesheet(1, texture)
        sprite:LoadGraphics()
        sprite:SetFrame("Idle", 0)
    end)

    if not ok and deleteMode then
        ok = pcall(function()
            sprite:Load("gfx/005.100_collectible.anm2", true)
            sprite:ReplaceSpritesheet(1, "gfx/MagicConch.png")
            sprite:LoadGraphics()
            sprite:SetFrame("Idle", 0)
        end)
    end

    if not ok then
        UpgradeHighlight._hudSpriteLoaded = false
        return nil
    end

    UpgradeHighlight._hudSprite = sprite
    UpgradeHighlight._hudSpriteLoaded = true
    UpgradeHighlight._hudLastDeleteMode = deleteMode
    return sprite
end

local function renderHudPulse()
    if not UpgradeHighlight._roomHasUpgradeable then
        return
    end

    local magicConch = rawget(_G, "MagicConch")
    if not magicConch or not magicConch.Config or not magicConch.Config.enabled then
        return
    end

    local sprite = loadHudSprite()
    if not sprite or not sprite.IsLoaded or not sprite:IsLoaded() then
        return
    end

    local frame = getFrame()
    local pulse = getDecayPulse(frame, HUD_PULSE_PERIOD, HUD_PULSE_DECAY_FRAMES)
    local iconX = (magicConch.Config.iconX ~= nil) and magicConch.Config.iconX or 430
    local iconY = (magicConch.Config.iconY ~= nil) and magicConch.Config.iconY or 265
    local pos = Vector(iconX, iconY)

    sprite.Scale = Vector(0.5, 0.5)
    local brightness = lerp(HUD_PULSE_BASE_BRIGHTNESS, HUD_PULSE_PEAK_BRIGHTNESS, pulse)
    local color = Color(
        brightness,
        brightness,
        brightness,
        lerp(HUD_PULSE_BASE_ALPHA, HUD_PULSE_PEAK_ALPHA, pulse),
        0.85 * pulse,
        0.85 * pulse,
        0.85 * pulse
    )
    sprite.Color = color
    sprite:Render(pos)
end

local function renderPreviews()
    local previews = UpgradeHighlight._previews
    if not tableHasEntries(previews) then
        return
    end
    local hud = Game():GetHUD()
    if hud and type(hud.IsVisible) == "function" and not hud:IsVisible() then
        return
    end
    for _, rec in pairs(previews) do
        if rec.t > 0 and not rec.failed then
            local pickup = livePreviewPickup(rec)
            if pickup then
                local ok, drawn = pcall(function()
                    local x, y = Preview.anchor(pickup)
                    return Preview.render(rec.layout, x, y, rec.t, UpgradeHighlight._previewClock + rec.phase)
                end)
                if ok then
                    rec.draws = rec.draws + 1
                    rec.sparks = rec.sparks + drawn.sparks
                    rec.pops = rec.pops + drawn.pops
                    rec.lastDrawn = drawn
                else
                    rec.failed = true
                    ConchBlessing.printError("[EvolutionPreview] render failed for " .. tostring(rec.identity) .. ": " .. tostring(drawn))
                end
            end
        end
    end
end

local function onRender()
    renderPreviews()
    renderHudPulse()
end

local function onUpdate()
    local frame = getFrame()
    local shouldScan = not UpgradeHighlight._lastScanFrame
        or frame - UpgradeHighlight._lastScanFrame >= ROOM_SCAN_INTERVAL

    if shouldScan then
        UpgradeHighlight.ScanRoom(frame)
    end
    updatePreviews()
end

-- Pickup callbacks only start a tree for a new pickup or follow a renewed
-- reference; whether a tracked pickup changed is judged in MC_POST_UPDATE.
local function onPickupUpdate(_, pickup)
    if not pickup or not isUpgradeablePickupVariant(pickup.Variant) then
        return
    end
    local hash = getPickupHash(pickup)
    local rec = UpgradeHighlight._previews[hash]
    if rec then
        if not livePreviewPickup(rec) then
            -- A native Morph (a reroll, a rotating pedestal turning) renews
            -- the entity under the same address. Follow it and put back a
            -- borrowed hop; the next update decides whether it still fits.
            rec.ptr = EntityPtr(pickup)
            restoreHop(rec, pickup)
        end
        return
    end
    local info = getPickupUpgradeInfo(pickup)
    if info then trackPreview(pickup, info) end
end

local function onRoomChanged()
    clearPreviews("room")
    UpgradeHighlight._lastScanFrame = nil
    UpgradeHighlight._roomUpgradeableCount = 0
    UpgradeHighlight._roomHasUpgradeable = false
    UpgradeHighlight.ScanRoom(getFrame())
end

if not UpgradeHighlight._callbacksRegistered then
    ConchBlessing:AddCallback(ModCallbacks.MC_POST_UPDATE, onUpdate)
    if ConchBlessing.AddPriorityCallback then
        ConchBlessing:AddPriorityCallback(ModCallbacks.MC_POST_RENDER, 100, onRender)
    else
        ConchBlessing:AddCallback(ModCallbacks.MC_POST_RENDER, onRender)
    end
    ConchBlessing:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, onRoomChanged)
    ConchBlessing:AddCallback(ModCallbacks.MC_POST_NEW_ROOM, onRoomChanged)
    ConchBlessing:AddCallback(ModCallbacks.MC_POST_NEW_LEVEL, onRoomChanged)
    ConchBlessing:AddCallback(ModCallbacks.MC_PRE_GAME_EXIT, function() clearPreviews("exit") end)
    ConchBlessing:AddCallback(ModCallbacks.MC_POST_PICKUP_INIT, onPickupUpdate, PickupVariant.PICKUP_COLLECTIBLE)
    ConchBlessing:AddCallback(ModCallbacks.MC_POST_PICKUP_INIT, onPickupUpdate, PickupVariant.PICKUP_TRINKET)
    ConchBlessing:AddCallback(ModCallbacks.MC_POST_PICKUP_UPDATE, onPickupUpdate, PickupVariant.PICKUP_COLLECTIBLE)
    ConchBlessing:AddCallback(ModCallbacks.MC_POST_PICKUP_UPDATE, onPickupUpdate, PickupVariant.PICKUP_TRINKET)
    -- A reload (luamod) must not leave an item layer mid-hop.
    if ModCallbacks.MC_PRE_MOD_UNLOAD then
        ConchBlessing:AddCallback(ModCallbacks.MC_PRE_MOD_UNLOAD, function(_, unloaded)
            if unloaded ~= ConchBlessing and unloaded ~= ConchBlessing.originalMod then return end
            clearPreviews("unload")
        end)
    end
    UpgradeHighlight._callbacksRegistered = true
end

return UpgradeHighlight
