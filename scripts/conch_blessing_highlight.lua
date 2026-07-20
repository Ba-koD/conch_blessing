-- Conch's Blessing - upgradeable pickup and Magic Conch HUD highlights

local UpgradeHighlight = ConchBlessing.UpgradeHighlight or {}
ConchBlessing.UpgradeHighlight = UpgradeHighlight

local FLAG_ORDER = { "positive", "neutral", "negative" }
local ROOM_SCAN_INTERVAL = 15
local ITEM_PULSE_PERIOD = 34
local ITEM_PULSE_ATTACK_FRAMES = 6
local ITEM_PULSE_DECAY_FRAMES = 30
local ITEM_PULSE_CYCLES = 5
local ITEM_PULSE_FRAMES = ITEM_PULSE_PERIOD * ITEM_PULSE_CYCLES
local HUD_PULSE_PERIOD = ITEM_PULSE_PERIOD
local HUD_PULSE_DECAY_FRAMES = ITEM_PULSE_DECAY_FRAMES

local BASE_COLOR = { r = 1, g = 1, b = 1, a = 1, ro = 0, go = 0, bo = 0 }
local ITEM_TARGET_COLORS = {
    positive = { r = 0.86, g = 1.32, b = 0.9, ro = 0.02, go = 0.38, bo = 0.04 },
    neutral = { r = 1.3, g = 1.18, b = 0.78, ro = 0.3, go = 0.2, bo = 0.02 },
    negative = { r = 1.28, g = 0.78, b = 0.74, ro = 0.36, go = 0.02, bo = 0.02 },
    multiple = { r = 0.42, g = 0.42, b = 0.42, ro = 0, go = 0, bo = 0 },
}
local HUD_PULSE_BASE_BRIGHTNESS = 1.0
local HUD_PULSE_PEAK_BRIGHTNESS = 2.15
local HUD_PULSE_BASE_ALPHA = 0.0
local HUD_PULSE_PEAK_ALPHA = 0.72

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

local function cloneColor(color)
    if not color then
        return {
            r = BASE_COLOR.r,
            g = BASE_COLOR.g,
            b = BASE_COLOR.b,
            a = BASE_COLOR.a,
            ro = BASE_COLOR.ro,
            go = BASE_COLOR.go,
            bo = BASE_COLOR.bo,
        }
    end

    return {
        r = color.Red or color.R or BASE_COLOR.r,
        g = color.Green or color.G or BASE_COLOR.g,
        b = color.Blue or color.B or BASE_COLOR.b,
        a = color.Alpha or color.A or BASE_COLOR.a,
        ro = color.ROffset or color.RO or color.RedOffset or BASE_COLOR.ro,
        go = color.GOffset or color.GO or color.GreenOffset or BASE_COLOR.go,
        bo = color.BOffset or color.BO or color.BlueOffset or BASE_COLOR.bo,
    }
end

local function toColor(color)
    color = color or BASE_COLOR
    return Color(
        color.r or BASE_COLOR.r,
        color.g or BASE_COLOR.g,
        color.b or BASE_COLOR.b,
        color.a or BASE_COLOR.a,
        color.ro or BASE_COLOR.ro,
        color.go or BASE_COLOR.go,
        color.bo or BASE_COLOR.bo
    )
end

local function resetPickupColor(pickup, baseColor)
    if not pickup or not pickup.Exists or not pickup:Exists() then
        return
    end
    local sprite = pickup:GetSprite()
    if sprite then
        sprite.Color = toColor(baseColor)
    end
end

local function lerp(a, b, t)
    return (a or 0) + (((b or 0) - (a or 0)) * t)
end

local function lerpColorTable(base, target, t)
    base = base or BASE_COLOR
    target = target or BASE_COLOR
    return {
        r = lerp(base.r or 1, target.r or 1, t),
        g = lerp(base.g or 1, target.g or 1, t),
        b = lerp(base.b or 1, target.b or 1, t),
        a = lerp(base.a or 1, target.a or base.a or 1, t),
        ro = lerp(base.ro or 0, target.ro or 0, t),
        go = lerp(base.go or 0, target.go or 0, t),
        bo = lerp(base.bo or 0, target.bo or 0, t),
    }
end

local function getDecayPulse(frame, period, decayFrames)
    local cycleFrame = frame % period
    if cycleFrame >= decayFrames then
        return 0
    end

    local decayProgress = cycleFrame / decayFrames
    return 0.5 + 0.5 * math.cos(decayProgress * math.pi)
end

local function getItemPulseIntensity(elapsed)
    local cycleFrame = elapsed % ITEM_PULSE_PERIOD
    if cycleFrame >= ITEM_PULSE_DECAY_FRAMES then
        return 0
    end

    if cycleFrame < ITEM_PULSE_ATTACK_FRAMES then
        local attackProgress = cycleFrame / ITEM_PULSE_ATTACK_FRAMES
        return 0.5 - (0.5 * math.cos(attackProgress * math.pi))
    end

    local decayFrames = ITEM_PULSE_DECAY_FRAMES - ITEM_PULSE_ATTACK_FRAMES
    if decayFrames <= 0 then
        return 0
    end

    local decayProgress = (cycleFrame - ITEM_PULSE_ATTACK_FRAMES) / decayFrames
    return 0.5 + (0.5 * math.cos(decayProgress * math.pi))
end

local function getModeTargetColor(mode, targets)
    return (targets or ITEM_TARGET_COLORS)[mode]
        or (targets or ITEM_TARGET_COLORS).multiple
        or BASE_COLOR
end

local function getCanonicalCycleSignature(itemIds)
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

    local parts = {}
    for step = 0, #itemIds - 1 do
        parts[#parts + 1] = tostring(itemIds[((bestOffset + step - 1) % #itemIds) + 1])
    end
    return "CYCLE:" .. table.concat(parts, ",")
end

local function getPickupOriginInfo(pickup)
    if not pickup or not isUpgradeablePickupVariant(pickup.Variant) then
        return nil
    end

    local rawId = pickup.SubType
    if type(rawId) ~= "number" or rawId <= 0 then
        return nil
    end

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
                local originKeys = {}
                for _, itemId in ipairs(itemIds) do
                    originKeys[#originKeys + 1] = "C:" .. tostring(itemId)
                end
                return {
                    identity = getCanonicalCycleSignature(itemIds),
                    originKeys = originKeys,
                }
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

    local mode = (#flags >= 2) and "multiple" or flags[1]
    return {
        originKey = originInfo.identity,
        mode = mode,
        flags = flags,
    }
end

local function getPickupState(pickup)
    local data = pickup:GetData()
    data.__conchBlessingUpgradeHighlight = data.__conchBlessingUpgradeHighlight or {}
    return data.__conchBlessingUpgradeHighlight
end

local function hasFinishedPulse(state, originKey)
    if not state or not originKey then
        return false
    end
    if state.doneOriginKey == originKey then
        return true
    end
    return state.doneOriginKeys and state.doneOriginKeys[originKey] == true
end

local function markPulseFinished(pickup, originKey)
    if not pickup or not originKey then
        return
    end

    local state = getPickupState(pickup)
    state.doneOriginKeys = state.doneOriginKeys or {}
    state.doneOriginKeys[originKey] = true
    state.doneOriginKey = originKey
    if state.activeOriginKey == originKey then
        state.activeOriginKey = nil
    end
end

local function hasActivePulseForPickup(pickup)
    local key = getPickupHash(pickup)
    return UpgradeHighlight._activePickups and UpgradeHighlight._activePickups[key] ~= nil
end

local function startPickupPulse(pickup, info, frame)
    if not pickup or not info or hasActivePulseForPickup(pickup) then
        return
    end

    local state = getPickupState(pickup)
    if hasFinishedPulse(state, info.originKey) then
        return
    end

    local sprite = pickup:GetSprite()
    local baseColor = cloneColor(sprite and sprite.Color or nil)
    local key = getPickupHash(pickup)

    UpgradeHighlight._activePickups = UpgradeHighlight._activePickups or {}
    UpgradeHighlight._activePickups[key] = {
        pickup = pickup,
        originKey = info.originKey,
        mode = info.mode,
        startFrame = frame,
        baseColor = baseColor,
    }

    state.activeOriginKey = info.originKey
end

local function maybeStartPickupPulse(pickup, frame)
    local info = getPickupUpgradeInfo(pickup)
    if not info then
        return false
    end

    startPickupPulse(pickup, info, frame)
    return true
end

local function applyPickupPulse(pulse, frame)
    local pickup = pulse.pickup
    if not pickup or not pickup.Exists or not pickup:Exists() then
        return true
    end
    local liveInfo = getPickupUpgradeInfo(pickup)
    if not liveInfo or liveInfo.originKey ~= pulse.originKey then
        resetPickupColor(pickup, pulse.baseColor)
        markPulseFinished(pickup, pulse.originKey)
        return true
    end

    local elapsed = frame - pulse.startFrame
    if elapsed >= ITEM_PULSE_FRAMES then
        resetPickupColor(pickup, pulse.baseColor)
        markPulseFinished(pickup, pulse.originKey)
        return true
    end

    local intensity = getItemPulseIntensity(elapsed)
    local base = pulse.baseColor or BASE_COLOR
    local target = getModeTargetColor(pulse.mode, ITEM_TARGET_COLORS)
    local color = lerpColorTable(base, target, intensity)

    local sprite = pickup:GetSprite()
    if sprite then
        sprite.Color = toColor(color)
    end

    return false
end

local function updateActivePickupPulses(frame)
    local active = UpgradeHighlight._activePickups
    if not tableHasEntries(active) then
        return
    end

    for key, pulse in pairs(active) do
        if applyPickupPulse(pulse, frame) then
            active[key] = nil
        end
    end
end

function UpgradeHighlight.StopForPickup(pickup)
    if not pickup then
        return
    end

    local active = UpgradeHighlight._activePickups
    if not tableHasEntries(active) then
        return
    end

    local key = getPickupHash(pickup)
    local pulse = active[key]
    if pulse then
        resetPickupColor(pickup, pulse.baseColor)
        active[key] = nil
    end
end

function UpgradeHighlight.ScanRoom(frame)
    frame = frame or getFrame()

    if not tableHasEntries(ConchBlessing.ItemMaps) then
        UpgradeHighlight._roomUpgradeableCount = 0
        UpgradeHighlight._roomHasUpgradeable = false
        UpgradeHighlight._roomPulseMode = nil
        UpgradeHighlight._lastScanFrame = frame
        return 0
    end

    local count = 0
    local roomMode = nil
    for _, entity in ipairs(Isaac.GetRoomEntities()) do
        local pickup = normalizePickup(entity)
        local info = pickup and getPickupUpgradeInfo(pickup) or nil
        if pickup and info then
            count = count + 1
            if not roomMode then
                roomMode = info.mode
            elseif roomMode ~= info.mode then
                roomMode = "multiple"
            end
            if info.mode == "multiple" then
                roomMode = "multiple"
            end
            startPickupPulse(pickup, info, frame)
        end
    end

    UpgradeHighlight._roomUpgradeableCount = count
    UpgradeHighlight._roomHasUpgradeable = count > 0
    UpgradeHighlight._roomPulseMode = roomMode
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

local function onUpdate()
    local frame = getFrame()
    local active = UpgradeHighlight._activePickups
    local shouldScan = not UpgradeHighlight._lastScanFrame
        or frame - UpgradeHighlight._lastScanFrame >= ROOM_SCAN_INTERVAL

    if shouldScan then
        UpgradeHighlight.ScanRoom(frame)
    elseif not tableHasEntries(active) and not UpgradeHighlight._roomHasUpgradeable then
        return
    end

    updateActivePickupPulses(frame)
end

local function onPickupInit(_, pickup)
    if not pickup or not isUpgradeablePickupVariant(pickup.Variant) then
        return
    end
    maybeStartPickupPulse(pickup, getFrame())
end

local function onPickupUpdate(_, pickup)
    if not pickup or not isUpgradeablePickupVariant(pickup.Variant) then
        return
    end
    if hasActivePulseForPickup(pickup) then
        return
    end
    maybeStartPickupPulse(pickup, getFrame())
end

local function onRoomChanged()
    local active = UpgradeHighlight._activePickups
    if tableHasEntries(active) then
        for _, pulse in pairs(active) do
            if pulse and pulse.pickup then
                resetPickupColor(pulse.pickup, pulse.baseColor)
            end
        end
    end

    UpgradeHighlight._activePickups = {}
    UpgradeHighlight._lastScanFrame = nil
    UpgradeHighlight._roomUpgradeableCount = 0
    UpgradeHighlight._roomHasUpgradeable = false
    UpgradeHighlight._roomPulseMode = nil
    UpgradeHighlight.ScanRoom(getFrame())
end

if not UpgradeHighlight._callbacksRegistered then
    ConchBlessing:AddCallback(ModCallbacks.MC_POST_UPDATE, onUpdate)
    if ConchBlessing.AddPriorityCallback then
        ConchBlessing:AddPriorityCallback(ModCallbacks.MC_POST_RENDER, 100, renderHudPulse)
    else
        ConchBlessing:AddCallback(ModCallbacks.MC_POST_RENDER, renderHudPulse)
    end
    ConchBlessing:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, onRoomChanged)
    ConchBlessing:AddCallback(ModCallbacks.MC_POST_NEW_ROOM, onRoomChanged)
    ConchBlessing:AddCallback(ModCallbacks.MC_POST_NEW_LEVEL, onRoomChanged)
    ConchBlessing:AddCallback(ModCallbacks.MC_POST_PICKUP_INIT, onPickupInit, PickupVariant.PICKUP_COLLECTIBLE)
    ConchBlessing:AddCallback(ModCallbacks.MC_POST_PICKUP_INIT, onPickupInit, PickupVariant.PICKUP_TRINKET)
    ConchBlessing:AddCallback(ModCallbacks.MC_POST_PICKUP_UPDATE, onPickupUpdate, PickupVariant.PICKUP_COLLECTIBLE)
    ConchBlessing:AddCallback(ModCallbacks.MC_POST_PICKUP_UPDATE, onPickupUpdate, PickupVariant.PICKUP_TRINKET)
    UpgradeHighlight._callbacksRegistered = true
end

return UpgradeHighlight
